// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * The [ConstantHandler] keeps track of compile-time constants,
 * initializations of global and static fields, and default values of
 * optional parameters.
 */
class ConstantHandler extends CompilerTask {
  final ConstantSystem constantSystem;

  /**
   * Contains the initial value of fields. Must contain all static and global
   * initializations of const fields. May contain eagerly compiled values for
   * statics and instance fields.
   */
  final Map<VariableElement, Constant> initialVariableValues;

  /** Map from compile-time constants to their JS name. */
  final Map<Constant, String> compiledConstants;

  /** The set of variable elements that are in the process of being computed. */
  final Set<VariableElement> pendingVariables;

  /** Caches the statics where the initial value cannot be eagerly compiled. */
  final Set<VariableElement> lazyStatics;


  ConstantHandler(Compiler compiler, this.constantSystem)
      : initialVariableValues = new Map<VariableElement, Dynamic>(),
        compiledConstants = new Map<Constant, String>(),
        pendingVariables = new Set<VariableElement>(),
        lazyStatics = new Set<VariableElement>(),
        super(compiler);
  String get name => 'ConstantHandler';

  void registerCompileTimeConstant(Constant constant) {
    Function ifAbsentThunk = (() {
      return constant.isFunction()
          ? null : compiler.namer.getFreshGlobalName("CTC");
    });
    compiledConstants.putIfAbsent(constant, ifAbsentThunk);
  }

  /**
   * Compiles the initial value of the given field and stores it in an internal
   * map. Returns the initial value (a constant) if it can be computed
   * statically. Returns [:null:] if the variable must be initialized lazily.
   *
   * [WorkItem] must contain a [VariableElement] refering to a global or
   * static field.
   */
  Constant compileWorkItem(WorkItem work) {
    return measure(() {
      assert(work.element.kind == ElementKind.FIELD
             || work.element.kind == ElementKind.PARAMETER
             || work.element.kind == ElementKind.FIELD_PARAMETER);
      VariableElement element = work.element;
      // Shortcut if it has already been compiled.
      Constant result = initialVariableValues[element];
      if (result != null) return result;
      if (lazyStatics.contains(element)) return null;
      result = compileVariableWithDefinitions(element, work.resolutionTree);
      assert(pendingVariables.isEmpty());
      return result;
    });
  }

  /**
   * Returns a compile-time constant, or reports an error if the element is not
   * a compile-time constant.
   */
  Constant compileConstant(VariableElement element) {
    return compileVariable(element, isConst: true);
  }

  /**
   * Returns the a compile-time constant if the variable could be compiled
   * eagerly. Otherwise returns `null`.
   */
  Constant compileVariable(VariableElement element, [bool isConst = false]) {
    return measure(() {
      if (initialVariableValues.containsKey(element)) {
        Constant result = initialVariableValues[element];
        return result;
      }
      TreeElements definitions = compiler.analyzeElement(element);
      Constant constant = compileVariableWithDefinitions(
          element, definitions, isConst: isConst);
      return constant;
    });
  }

  /**
   * Returns the a compile-time constant if the variable could be compiled
   * eagerly. If the variable needs to be initialized lazily returns `null`.
   * If the variable is `const` but cannot be compiled eagerly reports an
   * error.
   */
  Constant compileVariableWithDefinitions(VariableElement element,
                                          TreeElements definitions,
                                          [bool isConst = false]) {
    return measure(() {
      // Initializers for parameters must be const.
      isConst = isConst || element.modifiers.isConst()
          || !Elements.isStaticOrTopLevel(element);
      if (!isConst && lazyStatics.contains(element)) return null;

      Node node = element.parseNode(compiler);
      if (pendingVariables.contains(element)) {
        if (isConst) {
          MessageKind kind = MessageKind.CYCLIC_COMPILE_TIME_CONSTANTS;
          compiler.reportError(node,
                               new CompileTimeConstantError(kind, const []));
        } else {
          lazyStatics.add(element);
          return null;
        }
      }
      pendingVariables.add(element);

      SendSet assignment = node.asSendSet();
      Constant value;
      if (assignment === null) {
        // No initial value.
        value = new NullConstant();
      } else {
        Node right = assignment.arguments.head;
        value =
            compileNodeWithDefinitions(right, definitions, isConst: isConst);
      }
      if (value != null) {
        initialVariableValues[element] = value;
      } else {
        assert(!isConst);
        lazyStatics.add(element);
      }
      pendingVariables.remove(element);
      return value;
    });
  }

  Constant compileNodeWithDefinitions(Node node,
                                      TreeElements definitions,
                                      [bool isConst]) {
    return measure(() {
      assert(node !== null);
      CompileTimeConstantEvaluator evaluator = new CompileTimeConstantEvaluator(
          constantSystem, definitions, compiler, isConst);
      return evaluator.evaluate(node);
    });
  }

  /** Attempts to compile a constant expression. Returns null if not possible */
  Constant tryCompileNodeWithDefinitions(Node node, TreeElements definitions) {
    return measure(() {
      assert(node !== null);
      try {
        TryCompileTimeConstantEvaluator evaluator =
            new TryCompileTimeConstantEvaluator(constantSystem,
                                                definitions,
                                                compiler);
        return evaluator.evaluate(node);
      } on CompileTimeConstantError catch (exn) {
        return null;
      }
    });
  }

  /**
   * Returns a [List] of static non final fields that need to be initialized.
   * The list must be evaluated in order since the fields might depend on each
   * other.
   */
  List<VariableElement> getStaticNonFinalFieldsForEmission() {
    return initialVariableValues.getKeys().filter((element) {
      return element.kind == ElementKind.FIELD
          && !element.isInstanceMember()
          && !element.modifiers.isFinal();
    });
  }

  /**
   * Returns a [List] of static const fields that need to be initialized. The
   * list must be evaluated in order since the fields might depend on each
   * other.
   */
  List<VariableElement> getStaticFinalFieldsForEmission() {
    return initialVariableValues.getKeys().filter((element) {
      return element.kind == ElementKind.FIELD
          && !element.isInstanceMember()
          && element.modifiers.isFinal();
    });
  }

  List<VariableElement> getLazilyInitializedFieldsForEmission() {
    return new List<VariableElement>.from(lazyStatics);
  }

  List<Constant> getConstantsForEmission() {
    // We must emit dependencies before their uses.
    Set<Constant> seenConstants = new Set<Constant>();
    List<Constant> result = new List<Constant>();

    void addConstant(Constant constant) {
      if (!seenConstants.contains(constant)) {
        constant.getDependencies().forEach(addConstant);
        assert(!seenConstants.contains(constant));
        result.add(constant);
        seenConstants.add(constant);
      }
    }

    compiledConstants.forEach((Constant key, ignored) => addConstant(key));
    return result;
  }

  String getNameForConstant(Constant constant) {
    return compiledConstants[constant];
  }

  /** This function writes the constant in non-canonicalized form. */
  CodeBuffer writeJsCode(CodeBuffer buffer, Constant value) {
    value._writeJsCode(buffer, this);
    return buffer;
  }

  CodeBuffer writeConstant(CodeBuffer buffer, Constant value) {
    value._writeCanonicalizedJsCode(buffer, this);
    return buffer;
  }

  CodeBuffer writeJsCodeForVariable(CodeBuffer buffer,
                                    VariableElement element) {
    if (!initialVariableValues.containsKey(element)) {
      compiler.internalError("No initial value for given element",
                             element: element);
    }
    Constant constant = initialVariableValues[element];
    writeConstant(buffer, constant);
    return buffer;
  }

  /**
   * Write the contents of the quoted string to a [CodeBuffer] in
   * a form that is valid as JavaScript string literal content.
   * The string is assumed quoted by single quote characters.
   */
  static void writeEscapedString(DartString string,
                                 CodeBuffer buffer,
                                 void cancel(String reason)) {
    Iterator<int> iterator = string.iterator();
    while (iterator.hasNext()) {
      int code = iterator.next();
      if (code === $SQ) {
        buffer.add(@"\'");
      } else if (code === $LF) {
        buffer.add(@'\n');
      } else if (code === $CR) {
        buffer.add(@'\r');
      } else if (code === $LS) {
        // This Unicode line terminator and $PS are invalid in JS string
        // literals.
        buffer.add(@'\u2028');
      } else if (code === $PS) {
        buffer.add(@'\u2029');
      } else if (code === $BACKSLASH) {
        buffer.add(@'\\');
      } else {
        if (code > 0xffff) {
          cancel('Unhandled non-BMP character: U+${code.toRadixString(16)}');
        }
        // TODO(lrn): Consider whether all codes above 0x7f really need to
        // be escaped. We build a Dart string here, so it should be a literal
        // stage that converts it to, e.g., UTF-8 for a JS interpreter.
        if (code < 0x20) {
          buffer.add(@'\x');
          if (code < 0x10) buffer.add('0');
          buffer.add(code.toRadixString(16));
        } else if (code >= 0x80) {
          if (code < 0x100) {
            buffer.add(@'\x');
          } else {
            buffer.add(@'\u');
            if (code < 0x1000) {
              buffer.add('0');
            }
          }
          buffer.add(code.toRadixString(16));
        } else {
          buffer.addCharCode(code);
        }
      }
    }
  }

  String getJsConstructor(ClassElement element) {
    return compiler.namer.isolatePropertiesAccess(element);
  }
}

class CompileTimeConstantEvaluator extends AbstractVisitor {
  bool isEvaluatingConstant;
  final ConstantSystem constantSystem;
  final TreeElements elements;
  final Compiler compiler;

  CompileTimeConstantEvaluator(this.constantSystem,
                               this.elements,
                               this.compiler,
                               [bool isConst])
      : this.isEvaluatingConstant = isConst;

  Constant evaluate(Node node) {
    return node.accept(this);
  }

  Constant evaluateConstant(Node node) {
    bool oldIsEvaluatingConstant = isEvaluatingConstant;
    isEvaluatingConstant = true;
    Constant result = node.accept(this);
    isEvaluatingConstant = oldIsEvaluatingConstant;
    assert(result != null);
    return result;
  }

  Constant visitNode(Node node) {
    return signalNotCompileTimeConstant(node);
  }

  Constant visitLiteralBool(LiteralBool node) {
    return constantSystem.createBool(node.value);
  }

  Constant visitLiteralDouble(LiteralDouble node) {
    return constantSystem.createDouble(node.value);
  }

  Constant visitLiteralInt(LiteralInt node) {
    return constantSystem.createInt(node.value);
  }

  Constant visitLiteralList(LiteralList node) {
    if (!node.isConst())  {
      return signalNotCompileTimeConstant(node);
    }
    List<Constant> arguments = <Constant>[];
    for (Link<Node> link = node.elements.nodes;
         !link.isEmpty();
         link = link.tail) {
      arguments.add(evaluateConstant(link.head));
    }
    // TODO(floitsch): get type from somewhere.
    DartType type = null;
    Constant constant = new ListConstant(type, arguments);
    compiler.constantHandler.registerCompileTimeConstant(constant);
    return constant;
  }

  Constant visitLiteralMap(LiteralMap node) {
    if (!node.isConst()) {
      signalNotCompileTimeConstant(node);
      error(node);
    }
    List<StringConstant> keys = <StringConstant>[];
    Map<StringConstant, Constant> map = new Map<StringConstant, Constant>();
    for (Link<Node> link = node.entries.nodes;
         !link.isEmpty();
         link = link.tail) {
      LiteralMapEntry entry = link.head;
      Constant key = evaluateConstant(entry.key);
      if (!key.isString() || entry.key.asStringNode() === null) {
        MessageKind kind = MessageKind.KEY_NOT_A_STRING_LITERAL;
        compiler.reportError(entry.key, new ResolutionError(kind, const []));
      }
      StringConstant keyConstant = key;
      if (!map.containsKey(key)) keys.add(key);
      map[key] = evaluateConstant(entry.value);
    }
    List<Constant> values = <Constant>[];
    Constant protoValue = null;
    for (StringConstant key in keys) {
      if (key.value == const LiteralDartString(MapConstant.PROTO_PROPERTY)) {
        protoValue = map[key];
      } else {
        values.add(map[key]);
      }
    }
    bool hasProtoKey = (protoValue !== null);
    // TODO(floitsch): this should be a List<String> type.
    DartType keysType = null;
    ListConstant keysList = new ListConstant(keysType, keys);
    compiler.constantHandler.registerCompileTimeConstant(keysList);
    SourceString className = hasProtoKey
                             ? MapConstant.DART_PROTO_CLASS
                             : MapConstant.DART_CLASS;
    ClassElement classElement = compiler.jsHelperLibrary.find(className);
    classElement.ensureResolved(compiler);
    // TODO(floitsch): copy over the generic type.
    DartType type = new InterfaceType(classElement);
    compiler.enqueuer.codegen.registerInstantiatedClass(classElement);
    Constant constant = new MapConstant(type, keysList, values, protoValue);
    compiler.constantHandler.registerCompileTimeConstant(constant);
    return constant;
  }

  Constant visitLiteralNull(LiteralNull node) {
    return constantSystem.createNull();
  }

  Constant visitLiteralString(LiteralString node) {
    return constantSystem.createString(node.dartString, node);
  }

  Constant visitStringJuxtaposition(StringJuxtaposition node) {
    StringConstant left = evaluate(node.first);
    StringConstant right = evaluate(node.second);
    if (left == null || right == null) return null;
    return constantSystem.createString(
        new DartString.concat(left.value, right.value), node);
  }

  Constant visitStringInterpolation(StringInterpolation node) {
    StringConstant initialString = evaluate(node.string);
    if (initialString == null) return null;
    DartString accumulator = initialString.value;
    for (StringInterpolationPart part in node.parts) {
      Constant expression = evaluate(part.expression);
      DartString expressionString;
      if (expression.isNum() || expression.isBool()) {
        PrimitiveConstant primitive = expression;
        expressionString = new DartString.literal(primitive.value.toString());
      } else if (expression.isString()) {
        PrimitiveConstant primitive = expression;
        expressionString = primitive.value;
      } else {
        return signalNotCompileTimeConstant(part.expression);
      }
      accumulator = new DartString.concat(accumulator, expressionString);
      StringConstant partString = evaluate(part.string);
      if (partString == null) return null;
      accumulator = new DartString.concat(accumulator, partString.value);
    };
    return constantSystem.createString(accumulator, node);
  }

  // TODO(floitsch): provide better error-messages.
  Constant visitSend(Send send) {
    Element element = elements[send];
    if (Elements.isStaticOrTopLevelField(element)) {
      Constant result;
      if (element.modifiers !== null) {
        if (element.modifiers.isConst()) {
          result = compiler.compileConstant(element);
        } else if (element.modifiers.isFinal()) {
          // TODO(4516): remove support for final compile-time constants: if
          // isCompilingConstant is true don't compile the variable.
          result = compiler.compileVariable(element);
        }
      }
      if (result == null) return signalNotCompileTimeConstant(send);
      return result;
    } else if (Elements.isStaticOrTopLevelFunction(element)
               && send.isPropertyAccess) {
      compiler.codegenWorld.staticFunctionsNeedingGetter.add(element);
      Constant constant = new FunctionConstant(element);
      compiler.constantHandler.registerCompileTimeConstant(constant);
      return constant;
    } else if (send.isPrefix) {
      assert(send.isOperator);
      Constant receiverConstant = evaluate(send.receiver);
      if (receiverConstant == null) return null;
      Operator op = send.selector;
      Constant folded;
      switch (op.source.stringValue) {
        case "!":
          folded = constantSystem.not.fold(receiverConstant);
          break;
        case "-":
          folded = constantSystem.negate.fold(receiverConstant);
          break;
        case "~":
          folded = constantSystem.bitNot.fold(receiverConstant);
          break;
        default:
          compiler.internalError("Unexpected operator.", node: op);
          break;
      }
      if (folded === null) return signalNotCompileTimeConstant(send);
      return folded;
    } else if (send.isOperator && !send.isPostfix) {
      assert(send.argumentCount() == 1);
      Constant left = evaluate(send.receiver);
      Constant right = evaluate(send.argumentsNode.nodes.head);
      if (left == null || right == null) return null;
      Operator op = send.selector.asOperator();
      Constant folded = null;
      switch (op.source.stringValue) {
        case "+":
          folded = constantSystem.add.fold(left, right);
          break;
        case "-":
          folded = constantSystem.subtract.fold(left, right);
          break;
        case "*":
          folded = constantSystem.multiply.fold(left, right);
          break;
        case "/":
          folded = constantSystem.divide.fold(left, right);
          break;
        case "%":
          folded = constantSystem.modulo.fold(left, right);
          break;
        case "~/":
          folded = constantSystem.truncatingDivide.fold(left, right);
          break;
        case "|":
          folded = constantSystem.bitOr.fold(left, right);
          break;
        case "&":
          folded = constantSystem.bitAnd.fold(left, right);
          break;
        case "^":
          folded = constantSystem.bitXor.fold(left, right);
          break;
        case "||":
          folded = constantSystem.booleanOr.fold(left, right);
          break;
        case "&&":
          folded = constantSystem.booleanAnd.fold(left, right);
          break;
        case "<<":
          folded = constantSystem.shiftLeft.fold(left, right);
          break;
        case ">>":
          folded = constantSystem.shiftRight.fold(left, right);
          break;
        case "<":
          folded = constantSystem.less.fold(left, right);
          break;
        case "<=":
          folded = constantSystem.lessEqual.fold(left, right);
          break;
        case ">":
          folded = constantSystem.greater.fold(left, right);
          break;
        case ">=":
          folded = constantSystem.greaterEqual.fold(left, right);
          break;
        case "==":
          if (left.isPrimitive() && right.isPrimitive()) {
            folded = constantSystem.equal.fold(left, right);
          }
          break;
        case "===":
          if (left.isPrimitive() && right.isPrimitive()) {
            folded = constantSystem.identity.fold(left, right);
          }
          break;
        case "!=":
          if (left.isPrimitive() && right.isPrimitive()) {
            BoolConstant areEquals = constantSystem.equal.fold(left, right);
            if (areEquals === null) {
              folded = null;
            } else {
              folded = areEquals.negate();
            }
          }
          break;
        case "!==":
          if (left.isPrimitive() && right.isPrimitive()) {
            BoolConstant areIdentical =
                constantSystem.identity.fold(left, right);
            if (areIdentical === null) {
              folded = null;
            } else {
              folded = areIdentical.negate();
            }
          }
          break;
      }
      if (folded === null) return signalNotCompileTimeConstant(send);
      return folded;
    }
    return signalNotCompileTimeConstant(send);
  }

  Constant visitSendSet(SendSet node) {
    return signalNotCompileTimeConstant(node);
  }

  /** Returns the list of constants that are passed to the static function. */
  List<Constant> evaluateArgumentsToConstructor(Selector selector,
                                                Link<Node> arguments,
                                                FunctionElement target) {
    List<Constant> compiledArguments = <Constant>[];

    Function compileArgument = evaluateConstant;
    Function compileConstant = compiler.compileConstant;
    bool succeeded = selector.addArgumentsToList(arguments,
                                                 compiledArguments,
                                                 target,
                                                 compileArgument,
                                                 compileConstant,
                                                 compiler);
    assert(succeeded);
    return compiledArguments;
  }

  Constant visitNewExpression(NewExpression node) {
    if (!node.isConst()) {
      return signalNotCompileTimeConstant(node);
    }

    Send send = node.send;
    FunctionElement constructor = elements[send];
    ClassElement classElement = constructor.getEnclosingClass();
    if (classElement.isInterface()) {
      compiler.resolver.resolveMethodElement(constructor);
      constructor = constructor.defaultImplementation;
      classElement = constructor.getEnclosingClass();
    }

    Selector selector = elements.getSelector(send);
    List<Constant> arguments =
        evaluateArgumentsToConstructor(selector, send.arguments, constructor);
    ConstructorEvaluator evaluator =
        new ConstructorEvaluator(constructor, constantSystem, compiler);
    evaluator.evaluateConstructorFieldValues(arguments);
    List<Constant> jsNewArguments = evaluator.buildJsNewArguments(classElement);

    compiler.enqueuer.codegen.registerInstantiatedClass(classElement);
    // TODO(floitsch): take generic types into account.
    DartType type = classElement.computeType(compiler);
    Constant constant = new ConstructedConstant(type, jsNewArguments);
    compiler.constantHandler.registerCompileTimeConstant(constant);
    return constant;
  }

  Constant visitParenthesizedExpression(ParenthesizedExpression node) {
    return node.expression.accept(this);
  }

  error(Node node) {
    // TODO(floitsch): get the list of constants that are currently compiled
    // and present some kind of stack-trace.
    MessageKind kind = MessageKind.NOT_A_COMPILE_TIME_CONSTANT;
    compiler.reportError(node, new CompileTimeConstantError(kind, const []));
  }

  Constant signalNotCompileTimeConstant(Node node) {
    if (isEvaluatingConstant) {
      error(node);
    }
    // Else we don't need to do anything. The final handler is only
    // optimistically trying to compile constants. So it is normal that we
    // sometimes see non-compile time constants.
    // Simply return [:null:] which is used to propagate a failing
    // compile-time compilation.
    return null;
  }
}

class TryCompileTimeConstantEvaluator extends CompileTimeConstantEvaluator {
  TryCompileTimeConstantEvaluator(ConstantSystem constantSystem,
                                  TreeElements elements,
                                  Compiler compiler)
      : super(constantSystem, elements, compiler, isConst: true);

  error(Node node) {
    // Just fail without reporting it anywhere.
    throw new CompileTimeConstantError(
        MessageKind.NOT_A_COMPILE_TIME_CONSTANT, const []);
  }
}

class ConstructorEvaluator extends CompileTimeConstantEvaluator {
  FunctionElement constructor;
  final Map<Element, Constant> definitions;
  final Map<Element, Constant> fieldValues;

  ConstructorEvaluator(FunctionElement constructor,
                       ConstantSystem constantSystem,
                       Compiler compiler)
      : this.constructor = constructor,
        this.definitions = new Map<Element, Constant>(),
        this.fieldValues = new Map<Element, Constant>(),
        super(constantSystem,
              compiler.resolver.resolveMethodElement(constructor),
              compiler,
              isConst: true);

  Constant visitSend(Send send) {
    Element element = elements[send];
    if (Elements.isLocal(element)) {
      Constant constant = definitions[element];
      if (constant === null) {
        compiler.internalError("Local variable without value", node: send);
      }
      return constant;
    }
    return super.visitSend(send);
  }

  /**
   * Given the arguments (a list of constants) assigns them to the parameters,
   * updating the definitions map. If the constructor has field-initializer
   * parameters (like [:this.x:]), also updates the [fieldValues] map.
   */
  void assignArgumentsToParameters(List<Constant> arguments) {
    // Assign arguments to parameters.
    FunctionSignature parameters = constructor.computeSignature(compiler);
    int index = 0;
    parameters.forEachParameter((Element parameter) {
      Constant argument = arguments[index++];
      definitions[parameter] = argument;
      if (parameter.kind == ElementKind.FIELD_PARAMETER) {
        FieldParameterElement fieldParameterElement = parameter;
        fieldValues[fieldParameterElement.fieldElement] = argument;
      }
    });
  }

  void evaluateSuperOrRedirectSend(Selector selector,
                                   Link<Node> arguments,
                                   FunctionElement targetConstructor) {
    List<Constant> compiledArguments =
        evaluateArgumentsToConstructor(selector, arguments, targetConstructor);

    ConstructorEvaluator evaluator = new ConstructorEvaluator(
        targetConstructor, constantSystem, compiler);
    evaluator.evaluateConstructorFieldValues(compiledArguments);
    // Copy over the fieldValues from the super/redirect-constructor.
    evaluator.fieldValues.forEach((key, value) => fieldValues[key] = value);
  }

  /**
   * Runs through the initializers of the given [constructor] and updates
   * the [fieldValues] map.
   */
  void evaluateConstructorInitializers() {
    FunctionExpression functionNode = constructor.parseNode(compiler);
    NodeList initializerList = functionNode.initializers;

    bool foundSuperOrRedirect = false;

    if (initializerList !== null) {
      for (Link<Node> link = initializerList.nodes;
           !link.isEmpty();
           link = link.tail) {
        assert(link.head is Send);
        if (link.head is !SendSet) {
          // A super initializer or constructor redirection.
          Send call = link.head;
          FunctionElement targetConstructor = elements[call];
          Selector selector = elements.getSelector(call);
          Link<Node> arguments = call.arguments;
          evaluateSuperOrRedirectSend(selector, arguments, targetConstructor);
          foundSuperOrRedirect = true;
        } else {
          // A field initializer.
          SendSet init = link.head;
          Link<Node> initArguments = init.arguments;
          assert(!initArguments.isEmpty() && initArguments.tail.isEmpty());
          Constant fieldValue = evaluate(initArguments.head);
          fieldValues[elements[init]] = fieldValue;
        }
      }
    }

    if (!foundSuperOrRedirect) {
      // No super initializer found. Try to find the default constructor if
      // the class is not Object.
      ClassElement enclosingClass = constructor.getEnclosingClass();
      ClassElement superClass = enclosingClass.superclass;
      if (enclosingClass != compiler.objectClass) {
        assert(superClass !== null);
        assert(superClass.resolutionState == STATE_DONE);
        FunctionElement targetConstructor =
            superClass.lookupConstructor(superClass.name);
        if (targetConstructor === null) {
          compiler.internalError("no default constructor available",
                                 node: functionNode);
        }

        Selector selector = new Selector.call(superClass.name,
                                              enclosingClass.getLibrary(),
                                              0);
        evaluateSuperOrRedirectSend(selector,
                                    const EmptyLink<Node>(),
                                    targetConstructor);
      }
    }
  }

  /**
   * Simulates the execution of the [constructor] with the given
   * [arguments] to obtain the field values that need to be passed to the
   * native JavaScript constructor.
   */
  void evaluateConstructorFieldValues(List<Constant> arguments) {
    compiler.withCurrentElement(constructor, () {
      assignArgumentsToParameters(arguments);
      evaluateConstructorInitializers();
    });
  }

  List<Constant> buildJsNewArguments(ClassElement classElement) {
    List<Constant> jsNewArguments = <Constant>[];
    classElement.forEachInstanceField(
        includeBackendMembers: true,
        includeSuperMembers: true,
        f: (ClassElement enclosing, Element field) {
      Constant fieldValue = fieldValues[field];
      if (fieldValue === null) {
        // Use the default value.
        fieldValue = compiler.compileConstant(field);
      }
      jsNewArguments.add(fieldValue);
    });
    return jsNewArguments;
  }
}
