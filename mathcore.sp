#if defined __formula_mathcore
#endinput
#endif
#define __formula_mathcore

enum MOperator {
	OP_Plus,
	OP_Minus,
	OP_Mult,
	OP_Div,
	OP_Modulo,
	OP_Negate
}

enum CVarDataType {
	CVType_String,
	CVType_Float,
	CVType_Int
}

static bool convarAccess; //used to block cvar access for single eval calls
static StringMap varValues;
static StringMap targetValues; //cached results for target strings
static ArrayList tickAssignments; //prevent cyclic assignments

char evalError[PLATFORM_MAX_PATH];
//static void PutError(const char[] format, any...) { VFormat(evalError, sizeof(evalError), format, 2); }
static any PutError2(any value, const char[] format, any...) { VFormat(evalError, sizeof(evalError), format, 3); return value; }

void __mathcore_init() {
	if (varValues == null) varValues = new StringMap();
	if (targetValues == null) targetValues = new StringMap();
	if (tickAssignments == null) tickAssignments = new ArrayList(ByteCountToCells(128));
}

public void OnGameFrame() {
	//these values are only cached for a frame
	targetValues.Clear();
	tickAssignments.Clear();
}
static float getOrComputeTargets(const char[] target) {
	float value;
	if (targetValues.GetValue(target, value)) return value;
	int targets[MAXPLAYERS];
	char tname[1];
	bool tn_is_ml;
	int result = ProcessTargetString(target, 0, targets, MAXPLAYERS, 0, tname, 0, tn_is_ml);
	if (result > 0) value = float(result);
	targetValues.SetValue(target, value);
	return value;
}

/** parsetype: 0 root, 1 group, 2 arguments */
bool eval(const char[] formula, int parseType=0, int& consumed=0, float& returnValue, bool convars=true) {
	if (parseType==0) {
		//set the access flag for the remainder of this call
		convarAccess = convars;
	}
	ArrayStack valueStack = new ArrayStack();
	ArrayStack operandStack = new ArrayStack();
	int cursor;
	float value; char token; int type;
	char name[MAX_NAME_LENGTH];
	bool lastValue;
	MOperator op;
	int lastOpPriority; //since we only have +- and */ this is simply 1 or 2
	while (eSkipSpace(formula, cursor)) {
		if ((token = eGetToken(formula, cursor))) {
			if (token == '-') {
				if (lastValue) {
					if (lastOpPriority > 1) 
						for (int p=1; !!p;) { if ( (p=collapseStacks(valueStack, operandStack))<0 ) return false; } // completely collapse stacks
					lastOpPriority = 1;
					operandStack.Push(OP_Minus);
					lastValue = false;
				} else {
					//no priority here, because we handle negations when reading values
					if (!operandStack.Empty) {
						if ((op=operandStack.Pop())==OP_Negate) return PutError2(false,"Minus go brrrrt at %i", cursor);
						else operandStack.Push(op); //end of peek
					}
					operandStack.Push(OP_Negate);
				}
			} else if (token == '+') {
				if (!lastValue) return PutError2(false, "Operator is not unary +");
				if (lastOpPriority > 1) 
					for (int p=1; !!p;) { if ( (p=collapseStacks(valueStack, operandStack))<0 ) return false; } // completely collapse stacks
				lastOpPriority = 1;
				operandStack.Push(OP_Plus);
				lastValue = false;
			} else if (token == '*') {
				if (!lastValue) return PutError2(false, "Operator is not unary *");
				lastOpPriority = 2;
				operandStack.Push(OP_Mult);
				lastValue = false;
			} else if (token == '/') {
				if (!lastValue) return PutError2(false, "Operator is not unary /");
				lastOpPriority = 2;
				operandStack.Push(OP_Div);
				lastValue = false;
			} else if (token == '%') {
				if (!lastValue) return PutError2(false, "Operator is not unary %");
				lastOpPriority = 2;
				operandStack.Push(OP_Modulo);
				lastValue = false;
			} else if (token == '(') {
				if (lastValue) return PutError2(false, "Group cannot follow value");
				if (!evalSub(formula, cursor, 1, _, value)) return false;
				if (!operandStack.Empty) {
					if ((op=operandStack.Pop())==OP_Negate) value =- value;
					else operandStack.Push(op); //return op to stack if not negate
				}
				valueStack.Push(value);
				lastValue = true;
			} else if (token == ')' || token == ',') {
				if (!parseType) return PutError2(false, "Missing opening parathesis at %i", cursor);
				if (token == ',' && parseType != 2) return PutError2(false, "Too many arguments or not a function at %i", cursor);
				for (int p=1; !!p;) { if ( (p=collapseStacks(valueStack, operandStack))<0 ) return false; } // completely collapse stacks
				parseType = 0; //suppress the missing paranthesis warning
				break; //return soon
			} else {
				//might be a valid token, but not now
				return PutError2(false, "Syntax error around %i", cursor);
			}
		} else if (eGetValue(formula, cursor, value)) {
			if (lastValue) return PutError2(false, "Operator expected at %i", cursor);
			if (!operandStack.Empty) {
				if ((op=operandStack.Pop())==OP_Negate) value =- value;
				else operandStack.Push(op); //return op to stack if not negate
			}
			valueStack.Push(value);
			lastValue = true;
		} else if (( type = eGetLabel(formula, cursor, name, sizeof(name)) )) {
			if (type < 0) return false; //had error
			else if (lastValue) return PutError2(false, "Operator expected at %i", cursor);
			else if (type == 1) {
				if (!eSkipSpace(formula, cursor) || eGetToken(formula, cursor)!='(') {
					//reached EOF OR read wrong token
					return PutError2(false, "Function without arguments!");
				}
				//collect arguments based on function and get result
				if (StrEqual(name,"min",false)) {
					float arga, argb;
					if (!evalSub(formula, cursor, 2, _, arga)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 2");
					if (!evalSub(formula, cursor, 1, _, argb)) return false;
					value = arga<argb?arga:argb;
				} else if (StrEqual(name,"max",false)) {
					float arga, argb;
					if (!evalSub(formula, cursor, 2, _, arga)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 2");
					if (!evalSub(formula, cursor, 1, _, argb)) return false;
					value = arga>argb?arga:argb;
				} else if (StrEqual(name,"abs",false)) {
					if (!evalSub(formula, cursor, 1, _, value)) return false;
					value = value<0?-value:value;
				} else if (StrEqual(name,"round",false)) {
					if (!evalSub(formula, cursor, 1, _, value)) return false;
					value = float(RoundToNearest(value));
				} else if (StrEqual(name,"ceil",false)) {
					if (!evalSub(formula, cursor, 1, _, value)) return false;
					value = float(RoundToCeil(value));
				} else if (StrEqual(name,"floor",false)) {
					if (!evalSub(formula, cursor, 1, _, value)) return false;
					value = float(RoundToFloor(value));
				} else if (StrEqual(name,"if",false)) {
					float arg_cond, arg_true, arg_false;
					if (!evalSub(formula, cursor, 2, _, arg_cond)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 2");
					if (!evalSub(formula, cursor, 2, _, arg_true)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 3");
					if (!evalSub(formula, cursor, 1, _, arg_false)) return false;
					value = arg_cond>0?arg_true:arg_false;
				} else if (StrEqual(name,"lerp",false)) {
					float arga, argb, argt;
					if (!evalSub(formula, cursor, 2, _, arga)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 2");
					if (!evalSub(formula, cursor, 2, _, argb)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 3");
					if (!evalSub(formula, cursor, 1, _, argt)) return false;
					if (argt==0.0) value = arga;
					else if (argt==1.0) value = argb;
					else value = arga+argt*(argb-arga);
				} else if (StrEqual(name,"map",false)) {
					float arg_infrom, arg_into, arg_outfrom, arg_outto, arg_value;
					if (!evalSub(formula, cursor, 2, _, arg_infrom)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 2");
					if (!evalSub(formula, cursor, 2, _, arg_into)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 3");
					if (!evalSub(formula, cursor, 2, _, arg_outfrom)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 4");
					if (!evalSub(formula, cursor, 2, _, arg_outto)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 5");
					if (!evalSub(formula, cursor, 1, _, arg_value)) return false;
					float range_in = (arg_into-arg_infrom), range_out = (arg_outto-arg_outfrom);
					if (range_in == 0.0) range_in = 0.000001;
					value = (arg_value-arg_infrom)*range_out/range_in+arg_outfrom;
				} else if (StrEqual(name,"clamp",false)) {
					float arg_min, arg_val, arg_max;
					if (!evalSub(formula, cursor, 2, _, arg_min)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 2");
					if (!evalSub(formula, cursor, 2, _, arg_val)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 3");
					if (!evalSub(formula, cursor, 1, _, arg_max)) return false;
					//sort min/max
					if (arg_max < arg_min) { float tmp=arg_max;arg_max=arg_min;arg_min=tmp; }
					//...max(min,val)...
					value = arg_val < arg_min ? arg_min : arg_val;
					//min(...,max)
					if (value > arg_max) value = arg_max;
				} else if (StrEqual(name,"rand",false)) {
					float arga, argb;
					if (!evalSub(formula, cursor, 2, _, arga)) return false;
					if (formula[cursor-1]!=',') return PutError2(false, "Missing argument 2");
					if (!evalSub(formula, cursor, 1, _, argb)) return false;
					//sort min/max
					if (argb < arga) { float tmp=argb;argb=arga;arga=tmp; }
					argb = argb-arga; //range
					value = GetURandomFloat()*argb+arga;
				} else return PutError2(false, "Unknown function '%s'", name);
				valueStack.Push(value);
				lastValue = true;
			} else {
				if (lastValue) return PutError2(false, "Operator expected at %i", cursor);
				if (!getVariable(name,value)) return false;
				if (!operandStack.Empty) {
					if ((op=operandStack.Pop())==OP_Negate) value =- value;
					else operandStack.Push(op); //return op to stack if not negate
				}
				valueStack.Push(value);
				lastValue = true;
			}
		} else {
			return PutError2(false, "Syntax error around %i", cursor);
		}
	}
	if (!lastValue) return PutError2(false, "Missing value at the end");
	if (formula[cursor]==0 && parseType) return PutError2(false, "Missing closing parenthesis");
	consumed = cursor;
	for (int p=1; !!p;) { if ( (p=collapseStacks(valueStack, operandStack))<0 ) return false; } // completely collapse stacks
	if (valueStack.Empty) returnValue = 0.0;
	returnValue = valueStack.Pop();
	return true;
}
static bool evalSub(const char[] formula, int& cursor, int parseType, int& consumed=0, float& returnValue) {
	char subformula[PLATFORM_MAX_PATH];
	strcopy(subformula, sizeof(subformula), formula[cursor]);
	if (!eval(subformula, parseType, consumed, returnValue)) return false;
	cursor += consumed;
	return true;
}

/** 
 * return priority of up most op post collapse, or 0 if no op remains
 * return <0 if error
 */
static int collapseStacks(ArrayStack vals, ArrayStack ops) {
	//pop a value and an operator and note the operator priority
	//pop another value and another operator until priority decreases
	//push back last operator; should now have stacks in order
	//get one value into result buffer; both stacks now have equal size
	//pop one op and value and compute; this should now be left to right
	//once stacks are empty, push result value back as replacement
	// normally this whould have to be done until the op stacks priority is at least
	// as low as the priority of operators that are yet to be pushed onto (if any)
	if (ops.Empty) return 0; //nothing to do?
//	PrintToServer("Values:");
//	PrintStack(vals, true);
//	PrintToServer("Operands:");
//	PrintStack(ops, false);
	ArrayStack pvals = new ArrayStack();
	ArrayStack pops = new ArrayStack();
	int priority, postPriority;
	float value;
	MOperator op;
	while (!ops.Empty) {
		op = ops.Pop();
		value = vals.Pop();
		if (!priority) { //no priority yet, assign initial
			if (op <= OP_Plus) priority = 1;
			else priority = 2;
		} 
		if (op <= OP_Plus && priority == 2) { //priority dropped, we found the other bound of operators with equal prioriy
			ops.Push(op); //return op to inital stack, we are not resolving those yet
			pvals.Push(value); //but keep the value (as left/top most) initial value for later
			//with our limited set we have no choice, but after collapsing all */, we either get +- (1) or are done (0)
			//and since +- stacks should always empty (0) we can only return 1 from this priority
			postPriority = 1;
			break; //continue with calculating
		} else {
			pops.Push(op); //to some value, apply this operator...
			pvals.Push(value); //...with this value
		}
	}
	//move the last value to the secondary stack if we consume all operators, since we need the +1 imbalance again
	// this means we get the initial (left/top most) value here instead of through priority drop
	if (ops.Empty) {
		pvals.Push(vals.Pop());
		postPriority = 0;
	}
	//stacks passed into this function should now be of equal size
	//now pop the initial value from our stacks into the accumulator, evening bot stack sizes
	float result = pvals.Pop();
	while (!pops.Empty) {
		value = pvals.Pop();
		op = pops.Pop();
		switch (op) {
			case OP_Minus: result -= value;
			case OP_Plus: result += value;
			case OP_Mult: result *= value;
			case OP_Div: result /= value;
			case OP_Modulo: {
				result = result - RoundToZero(result / value) * value;
			}
			default: return PutError2(-1, "Unexpected operator during stack resolution %i", op);
		}
	}
	vals.Push(result); //value stack should be bigger by 1 again, working fine with binary ops
	return postPriority;
}
//static void PrintStack(ArrayStack stack, bool asFloat) {
//	ArrayStack other = new ArrayStack();
//	int size;
//	while (!stack.Empty) {
//		other.Push(stack.Pop());
//		size++;
//	}
//	while (!other.Empty) {
//		any val = other.Pop();
//		stack.Push(val);
//		if (asFloat)
//			PrintToServer("%4i :  %f", size--, val);
//		else
//			PrintToServer("%4i :  %i", size--, val);
//	}
//}

/** return if more tokens are expected */
static bool eSkipSpace(const char[] f, int& cursor) {
	while (f[cursor]==' ' && f[cursor]!=0) cursor++;
	return f[cursor]!=0;
}
/** return true if a value was read */
static bool eGetValue(const char[] f, int& cursor, float& value) {
	int read = StringToFloatEx(f[cursor], value);
	cursor += read;
	return !!read;
}
/**
 * return label type (>0) if label, 0 if no label, and -1 if error
 */
static int eGetLabel(const char[] f, int& cursor, char[] name, int maxsize) {
	int type;
	int to=cursor;
	if (f[cursor]=='$') {
		type = 2; //variable
		to++;
	} else if (f[cursor]=='@') {
		type = 4; //target string
		to++;
	}
	while ('a'<=f[to]<='z' || 'A'<=f[to]<='Z' || '0'<=f[to]<='9' ||
		f[to]=='_' || (f[to]=='!'&&type==4)) {to++;}
	int len=to-cursor;
	if (len > (type?1:0)) {
		int buf = len+1;
		if (maxsize < buf) buf = maxsize;
		strcopy(name, buf, f[cursor]);
		if (!type) {
			if (isKeyword(name)) type = 1; //keyword
			else type = 3; //probably convar
		}
		cursor += len;
	} else {
		if (type==2) {
			return PutError2(-1, "Empty variable name at %i", cursor);
		} else if (type==4) {
			return PutError2(-1, "Empty target selector at %i", cursor);
		}
	}
	return type;
}
static char eGetToken(const char[] f, int& cursor) {
	char result;
	switch (f[cursor]) {
		case '+','-','*','/','%','(',')',',': result = f[cursor];
		//quare brackets are aliased here to make formulas work
		// better with games where valve broke double-quotes
		case '[': result = '(';
		case ']': result = ')';
		default: return 0;
	}
	cursor++;
	return result;
}
static bool isKeyword(const char[] n) {
	if (StrEqual(n,"min",false)) return true;
	else if (StrEqual(n,"max",false)) return true;
	else if (StrEqual(n,"abs",false)) return true;
	else if (StrEqual(n,"round",false)) return true;
	else if (StrEqual(n,"ceil",false)) return true;
	else if (StrEqual(n,"floor",false)) return true;
	else if (StrEqual(n,"if",false)) return true;
	else if (StrEqual(n,"lerp",false)) return true;
	else if (StrEqual(n,"map",false)) return true;
	else if (StrEqual(n,"clamp",false)) return true;
	else if (StrEqual(n,"rand",false)) return true;
	else return false;
}

bool getVariable(const char[] name, float& returnValue) {
	if (name[0]=='$') {
		if (!varValues.GetValue(name, returnValue))
			return PutError2(false, "Variable %s was not assigned a value", name);
	} else if (name[0]=='@') {
		returnValue = getOrComputeTargets(name);
	} else {
		if (!convarAccess) return PutError2(false, "You are not allowed to read convars!");
		ConVar cvar = FindConVar(name);
		if (cvar == null) return PutError2(false, "ConVar %s does not exist", name);
		returnValue = cvar.FloatValue;
		delete cvar;
	}
	return true;
}
bool setVariable(const char[] name, float value, bool notify) {
	if (name[0]=='$') {
		notify &= tickAssignments.FindString(name) == -1;
		if (notify) {
			tickAssignments.PushString(name);
			if(NotifyVariableChanged(name, value) >= Plugin_Handled) return true;
		}
		varValues.SetValue(name, value);
		if (notify) NotifyVariableChangedPost(name, value);
	} else if (name[0]=='@') {
		return PutError2(false, "Can't set value for target selectors (%s)", name);
	} else {
		ConVar cvar = FindConVar(name);
		if (cvar == null) return PutError2(false, "ConVar %s does not exist", name);
		CVarDataType type = GetConVarDataType(cvar);
		if (type == CVType_String) return PutError2(false, "Can not assign to String ConVar %s", name);
		else if (type == CVType_Int) cvar.SetInt(RoundToZero(value));
		else cvar.SetFloat(value);
		delete cvar;
	}
	return true;
}

CVarDataType GetConVarDataType(ConVar cvar) {
	char buf[64];
	cvar.GetDefault(buf,sizeof(buf));
	int slen = strlen(buf);
	int tmp;
	float tmp2;
	if (slen == 0) return CVType_String; //empty string defaul hints at string
	else if (StringToIntEx(buf,tmp) == slen) return CVType_Int; //We could parse default completely as int
	else if (StringToFloatEx(buf,tmp2) == slen) return CVType_Float; //We could completely parse default as float (with dot)
	else return CVType_String; //non numeric is string
}
