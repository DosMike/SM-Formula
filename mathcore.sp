#if !defined __formula
#error Not compiling from main file!
#endif
#if defined __formula_mathcore
#endinput
#endif
#define __formula_mathcore

enum MOperator {
	OP_MetaInvalid=-1,
	OP_Or,     //p1
	OP_And,    //p1
	OP_CmpLSS, //p2
	OP_CmpLEQ, //p2
	OP_CmpEQU, //p2
	OP_CmpGEQ, //p2
	OP_CmpGTR, //p2
	OP_CmpNEQ, //p2
	OP_Plus,   //p3
	OP_Minus,  //p3
	OP_Mult,   //p4
	OP_Div,    //p4
	OP_Modulo, //p4
	OP_Negate, //"p5", as rtl consumed immediately
	OP_MetaOpen,
	OP_MetaClose,
	OP_MetaComma,
}

enum CVarDataType {
	CVType_String,
	CVType_Float,
	CVType_Int
}

static int convarAccess; //used to block cvar access for single eval calls
static StringMap varValues;
static StringMap targetValues; //cached results for target strings
static ArrayList tickAssignments; //prevent cyclic assignments

char evalError[PLATFORM_MAX_PATH];
//static void PutError(const char[] format, any...) { VFormat(evalError, sizeof(evalError), format, 2); }
any PutError2(any value, const char[] format, any...) { VFormat(evalError, sizeof(evalError), format, 3); return value; }

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

int GetPriorityOp(MOperator op) {
	switch (op) {
		case OP_Or,OP_And: 
			return 1;
		case OP_CmpLSS, OP_CmpLEQ, OP_CmpEQU, OP_CmpGEQ, OP_CmpGTR, OP_CmpNEQ: 
			return 2;
		case OP_Plus, OP_Minus:
			return 3;
		case OP_Mult, OP_Div, OP_Modulo:
			return 4;
		default:
			return 5;
	}
}

/** parsetype: 0 root, 1 group, 2 arguments
 * asClient is the client to use for permission checks on cvars, or -1 to block access
 */
bool eval(const char[] formula, int parseType=0, int& consumed=0, float& returnValue, int asClient=0) {
	if (parseType==0) {
		//set the access flag for the remainder of this call
		convarAccess = asClient;
	}
	ArrayStack valueStack = new ArrayStack();
	ArrayStack operandStack = new ArrayStack();
	int cursor;
	float value; MOperator token; int type;
	char name[MAX_OUTPUT_LENGTH];
	bool lastValue;
	MOperator op;
	int lastOpPriority, priority;
	while (eSkipSpace(formula, cursor)) {
		if ((token = eGetToken(formula, cursor, priority))!=OP_MetaInvalid) switch (token) {
			case OP_MetaOpen: {
				if (lastValue) return PutError2(false, "Group cannot follow value");
				if (!evalSub(formula, cursor, 1, _, value)) return false;
				if (!operandStack.Empty) {
					if ((op=operandStack.Pop())==OP_Negate) value =- value;
					else operandStack.Push(op); //return op to stack if not negate
				}
				valueStack.Push(value);
				lastValue = true;
			}
			case OP_MetaClose,OP_MetaComma: {
				if (!parseType) return PutError2(false, "Missing opening parathesis at %i", cursor);
				if (token == OP_MetaComma && parseType != 2) return PutError2(false, "Too many arguments or not a function at %i", cursor);
				for (int p=1; !!p;) { if ( (p=collapseStacks(valueStack, operandStack))<0 ) return false; } // completely collapse stacks
				parseType = 0; //suppress the missing paranthesis warning
				break; //return soon
			}
			case OP_Minus: {
				if (lastValue) {
					if (lastOpPriority > priority) 
						for (int p=priority; !!p;) { if ( (p=collapseStacks(valueStack, operandStack))<0 ) return false; } // completely collapse stacks
					lastOpPriority = priority;
					operandStack.Push(OP_Minus);
					lastValue = false;
				} else {
					//no priority here, because we handle negations when reading values (rtl)
					if (!operandStack.Empty) {
						if ((op=operandStack.Pop())==OP_Negate) return PutError2(false,"Minus go brrrrt at %i", cursor);
						else operandStack.Push(op); //end of peek
					}
					operandStack.Push(OP_Negate);
				}
			}
			case OP_Plus,OP_Mult,OP_Div,OP_Modulo,OP_CmpLSS,OP_CmpLEQ,OP_CmpEQU,OP_CmpGEQ,OP_CmpGTR,OP_CmpNEQ,OP_And,OP_Or: {
				if (!lastValue) return PutError2(false, "Operator is not unary!");
				if (lastOpPriority > priority) 
					for (int p=priority; !!p;) { if ( (p=collapseStacks(valueStack, operandStack))<0 ) return false; } // completely collapse stacks
				lastOpPriority = priority;
				operandStack.Push(token);
				lastValue = false;
			}
			default: {
				//might be a valid token, but not now
				return PutError2(false, "Syntax error around %i", cursor);
			}
		} else if ((type = eGetValue(formula, cursor, value))!=0) {
			if (type < 0) return false;//already pushed error
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
				if (!eSkipSpace(formula, cursor) || eGetToken(formula, cursor)!=OP_MetaOpen) {
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
				if (!getVariable(name,value,asClient)) return false;
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
	char subformula[MAX_FORMULA_LENGTH];
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
	int oppr;
	while (!ops.Empty) {
		op = ops.Pop();
		value = vals.Pop();
		oppr = GetPriorityOp(op);
		if (oppr < 1)
			return PutError2(-1, "Unknown operator on stack");
		if (!priority) //no priority yet, assign initial
			priority = oppr;
		if (oppr < priority) { //priority dropped, we found the other bound of operators with equal prioriy
			ops.Push(op); //return op to inital stack, we are not resolving those yet
			pvals.Push(value); //but keep the value (as left/top most) initial value for later
			postPriority = oppr; //after collapse we remain with this as highest priority
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
			case OP_CmpLSS: result = (result < value) ? 1.0 : 0.0;
			case OP_CmpLEQ: result = (result <= value) ? 1.0 : 0.0;
			case OP_CmpEQU: result = (result == value) ? 1.0 : 0.0;
			case OP_CmpGEQ: result = (result >= value) ? 1.0 : 0.0;
			case OP_CmpGTR: result = (result > value) ? 1.0 : 0.0;
			case OP_CmpNEQ: result = (result != value) ? 1.0 : 0.0;
			case OP_And: result = (result > 0.0 && value > 0.0) ? 1.0 : 0.0;
			case OP_Or: result = (result > 0.0 || value > 0.0) ? 1.0 : 0.0;
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
static int eGetValue(const char[] f, int& cursor, float& value) {
	int read = StringToFloatEx(f[cursor], value);
	cursor += read;
	if (read > 0 && f[cursor]=='d') {
		if (FloatFraction(value) >= 0.000001) return PutError2(-1, "Error in dice notation: Integer expected for dice count");
		cursor++;
		int diecount = RoundToNearest(value);
		read = StringToFloatEx(f[cursor], value);
		if (read == 0 || FloatFraction(value) >= 0.000001) return PutError2(-1, "Error in dice notation: Integer expected for pips count");
		cursor += read;
		int faces = RoundToNearest(value);
		if (diecount > 100 || faces > 1000) return PutError2(-1, "Error in dice notation: Limits exceeded, max is 100d1000");
		value = float(diecount);
		for (;diecount>0;diecount--) value += float(RoundToZero(GetURandomFloat()*faces));
	}
	return read;
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
static MOperator eGetToken(const char[] f, int& cursor, int& priority=0) {
	MOperator result;
	switch (f[cursor]) {
		//quare brackets are aliased here to make formulas work
		// better with games where valve broke double-quotes
		case '(','[': {
			result = OP_MetaOpen;
			priority = 0;
		}
		case ')',']': {
			result = OP_MetaClose;
			priority = 0;
		}
		case ',': {
			result = OP_MetaComma;
			priority = 0;
		}
		case '*': {
			result = OP_Mult;
			priority = 4;
		}
		case '/': {
			result = OP_Div;
			priority = 4;
		}
		case '%': {
			result = OP_Modulo;
			priority = 4;
		}
		case '+': {
			result = OP_Plus;
			priority = 3;
		}
		case '-': {
			result = OP_Minus;
			priority = 3;
		}
		case '<': {
			if (f[cursor+1] == '=') {
				cursor++;
				result = OP_CmpLEQ;
			} else if (f[cursor+1] == '>') {
				cursor++;
				result = OP_CmpNEQ;
			} else {
				result = OP_CmpLSS;
			}
			priority = 2;
		}
		case '>': {
			if (f[cursor+1] == '=') {
				cursor++;
				result = OP_CmpGEQ;
			} else {
				result = OP_CmpGTR;
			}
			priority = 2;
		}
		case '=': {
			result = OP_CmpEQU;
			priority = 2;
		}
		case '&': {
			result = OP_And;
			priority = 1;
		}
		case '|': {
			result = OP_Or;
			priority = 1;
		}
		default: {
			return OP_MetaInvalid;
		}
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

bool getVariable(const char[] name, float& returnValue, int asClient=0) {
	if (name[0]=='$') {
		if (asClient) {
			char ownedname[MAX_NAME_LENGTH];
			Format(ownedname,sizeof(ownedname),"%i%s",GetClientUserId(asClient),name);
			if (varValues.GetValue(ownedname, returnValue)) {
				return true; //this exists as user var, use the user var
			}
			//otherwise continue and try to get global var
		}
		if (!varValues.GetValue(name, returnValue))
			return PutError2(false, "Variable %s was not assigned a value", name);
	} else if (name[0]=='@') {
		returnValue = getOrComputeTargets(name);
	} else {
		ConVar cvar = FindConVar(name);
		if (cvar == null) return PutError2(false, "ConVar %s does not exist", name);
		if (convarAccess<0 || !IsClientAllowedToChangeCvar(convarAccess, cvar)) return PutError2(false, "You are not allowed to read convars!");
		if (GetConVarDataType(cvar) == CVType_String) return PutError2(false, "ConVar %s is not default numeric", name);
		returnValue = cvar.FloatValue;
		delete cvar;
	}
	return true;
}
bool setVariable(const char[] name, float value, bool notify, int asClient=0) {
	if (name[0]=='$') {
		notify &= tickAssignments.FindString(name) == -1;
		if (notify) tickAssignments.PushString(name);
		//check if this exists as global var
		float dummy;
		if (asClient==0 || varValues.GetValue(name, dummy)) {
			//set the global value if it is a global var
			varValues.SetValue(name, value);
			if (notify) NotifyVariableChanged(name, value, 0);
		} else {
			//otherwise create the var for the client
			char ownedname[MAX_NAME_LENGTH];
			Format(ownedname, sizeof(ownedname), "%i%s",GetClientUserId(asClient),name);
			varValues.SetValue(ownedname, value);
			if (notify) NotifyVariableChanged(name, value, asClient);
		}
	} else if (name[0]=='@') {
		return PutError2(false, "Can't set value for target selectors (%s)", name);
	} else {
		ConVar cvar = FindConVar(name);
		if (cvar == null) return PutError2(false, "ConVar %s does not exist", name);
		if (convarAccess<0 || !IsClientAllowedToChangeCvar(asClient, cvar))
			return PutError2(false, "You are not allowed to read convars!");
		CVarDataType type = GetConVarDataType(cvar);
		if (type == CVType_String) return PutError2(false, "Can not assign to String ConVar %s", name);
		else if (type == CVType_Int) cvar.SetInt(RoundToZero(value));
		else cvar.SetFloat(value);
		delete cvar;
	}
	return true;
}

void dropVariables(int owner) {
	if (!(1<=owner<=MaxClients)) return;
	
	char buffer[MAX_NAME_LENGTH];
	char uid[32];
	Format(uid,sizeof(uid),"%i$",GetClientUserId(owner));
	
	StringMapSnapshot snap = varValues.Snapshot();
	for (int i=snap.Length-1;i>=0;i-=1) {
		snap.GetKey(i,buffer,sizeof(buffer));
		if (StrContains(buffer,uid)==0) {
			//variable starts with this uid$, so delete
			varValues.Remove(buffer);
		}
	}
	delete snap;
}

CVarDataType GetConVarDataType(ConVar cvar) {
	char buf[32];
	cvar.GetDefault(buf,sizeof(buf));
	int slen = strlen(buf);
	int tmp;
	float tmp2;
	if (slen == 0) return CVType_String; //empty string defaul hints at string
	else if (StringToIntEx(buf,tmp) == slen) return CVType_Int; //We could parse default completely as int
	else if (StringToFloatEx(buf,tmp2) == slen) return CVType_Float; //We could completely parse default as float (with dot)
	else return CVType_String; //non numeric is string
}
