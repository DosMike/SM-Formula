#if defined __formula_api
#endinput
#endif
#define __formula_api

#define TriggerToIdBits(%1) (((%1)&0x0fff)<<20)
#define TriggerOfIdBits(%1) (((%1)>>20)&0x0fff)
#define ActionMask 0x000fffff
#define TriggerMask 0xfff00000

enum eFormulaSource {
	FSource_Plugin,
	FSource_Config,
}

enum struct FormulaAction {
	int key; //trigger id & action pseudo
	eFormulaSource source;
	Handle owner; //for error printing
	char output[128];
	char formula[512];
}
ArrayList triggerNames;
static ArrayList autoActions;
GlobalForward fwdVariableChanged;
GlobalForward fwdVariableChangedPost;

void __api_init() {
	if (triggerNames == null) triggerNames = new ArrayList(ByteCountToCells(128));
	if (autoActions == null)
		autoActions = new ArrayList(sizeof(FormulaAction));
	else
		autoActions.Clear();
	if (fwdVariableChanged == null)
		fwdVariableChanged = new GlobalForward("OnFormulaVariableChanged", ET_Hook, Param_String, Param_FloatByRef);
	if (fwdVariableChangedPost == null)
		fwdVariableChangedPost = new GlobalForward("OnFormulaVariableChangedPost", ET_Ignore, Param_String, Param_Float);
}

void __removeConfigActions() {
	int c;
	for (int i=autoActions.Length-1;i>=0;i--) {
		if (autoActions.Get(i,FormulaAction::source)==FSource_Config) {
			autoActions.Erase(i);
			c++;
		}
	}
	PrintToServer("Dropped %i Actions", c);
}


// == native stuff

static void checkWordChars(const char[] string, int first=0) {
	for (int i=first;string[i]!=0;i++)
		if (!('a'<=string[i]<='z' || 'A'<=string[i]<='Z' || '0'<=string[i]<='9' || string[i]=='_'))
			ThrowNativeError(SP_ERROR_NATIVE, "Invalid character in name. Use \\w characters!");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("Formula_Eval", Native_Formula_Eval);
	CreateNative("Formula_SetVariable", Native_Formula_SetVariable);
	CreateNative("Formula_GetVariable", Native_Formula_GetVariable);
	CreateNative("Evaluator.Fire", Native_Evaluator_Fire);
	CreateNative("Evaluator.Close", Native_Evaluator_Close);
	CreateNative("MathTrigger.MathTrigger", Native_MathTrigger_new);
	CreateNative("MathTrigger.AddFormula", Native_MathTrigger_AddFormula);
	CreateNative("MathTrigger.Fire", Native_MathTrigger_Fire);
	RegPluginLibrary("formula");
}
// native bool Formula_Eval(const char[] formula, float& result, bool convars=true, char[] error="", int maxsize=0)
public any Native_Formula_Eval(Handle plugin, int argc) {
	//get formula
	int formulaLen, error;
	if ((error=GetNativeStringLength(1, formulaLen))!=SP_ERROR_NONE) ThrowNativeError(error, "Could not get formula");
	char[] formula = new char[++formulaLen];
	GetNativeString(1, formula, formulaLen);
	//other in params
	bool useConvars = view_as<bool>(GetNativeCell(3));
	error = GetNativeCell(5); //buffer size
	//compute and return
	float result;
	if (eval(formula, 0, _, result, useConvars)) {
		SetNativeCellRef(2, result);
		return true;
	} else {
		SetNativeString(4, evalError, error);
		return false;
	}
}
// native void Formula_SetVariable(const char[] name, float value)
public any Native_Formula_SetVariable(Handle plugin, int argc) {
	//get variable name with $ prefix
	int varnameLen, error;
	if ((error=GetNativeStringLength(1, varnameLen))!=SP_ERROR_NONE) ThrowNativeError(error, "Could not get formula");
	varnameLen+=2;
	char[] varname = new char[varnameLen];
	varname[0]='$';
	GetNativeString(1, varname[1], varnameLen-1);
	//validate name
	checkWordChars(varname, 1);
	float value = view_as<float>(GetNativeCell(2));
	setVariable(varname, value, false);
}
// native float Formula_GetVariable(const char[] name, bool& isset=false)
public any Native_Formula_GetVariable(Handle plugin, int argc) {
	//get variable name with $ prefix
	int varnameLen, error;
	if ((error=GetNativeStringLength(1, varnameLen))!=SP_ERROR_NONE) ThrowNativeError(error, "Could not get formula");
	varnameLen+=2;
	char[] varname = new char[varnameLen];
	varname[0]='$';
	GetNativeString(1, varname[1], varnameLen-1);
	//validate name
	checkWordChars(varname, 1);
	float value;
	if (getVariable(varname, value)) {
		SetNativeCellRef(2, true);
		return value;
	} else {
		SetNativeCellRef(2, false);
		return 0.0;
	}
}
// public native MathTrigger::MathTrigger(const char[] name)
public any Native_MathTrigger_new(Handle plugin, int argc) {
	//get name
	int tnameLen, error;
	if ((error=GetNativeStringLength(1, tnameLen))!=SP_ERROR_NONE) ThrowNativeError(error, "Could not get formula");
	char[] tname = new char[++tnameLen];
	GetNativeString(1, tname, tnameLen);
	checkWordChars(tname);
	//doit
	int trigger = RegisterTrigger(tname);
	if (trigger == -1) ThrowNativeError(SP_ERROR_NATIVE, "Could not create MathTrigger - Limit exhausted!");
	return trigger;
}
// public native Evaluator MathTrigger::AddFormula(const char[] output, const char[] formula)
public any Native_MathTrigger_AddFormula(Handle plugin, int argc) {
	int trigger = GetNativeCell(1);
	//get output
	int outputLen, error;
	if ((error=GetNativeStringLength(2, outputLen))!=SP_ERROR_NONE) ThrowNativeError(error, "Could not get formula");
	char[] output = new char[++outputLen];
	GetNativeString(2, output, outputLen);
	checkWordChars(output);
	//get formula
	int formulaLen;
	if ((error=GetNativeStringLength(3, formulaLen))!=SP_ERROR_NONE) ThrowNativeError(error, "Could not get formula");
	char[] formula = new char[++formulaLen];
	GetNativeString(3, formula, formulaLen);
	//doit
	int evaluator = CreateAction(plugin, trigger, output, formula);
	if (evaluator == -1) ThrowNativeError(SP_ERROR_NATIVE, "Could not create Evaluator - MathTrigger is invalid!");
	else if (evaluator == -2) ThrowNativeError(SP_ERROR_NATIVE, "Could not create Evaluator - Limit exhausted!");
	return evaluator;
}
// public native void MathTrigger::Fire()
public any Native_MathTrigger_Fire(Handle plugin, int argc) {
	int trigger = GetNativeCell(1);
	if (!TriggerAction(trigger))
		ThrowNativeError(SP_ERROR_NATIVE, "MathTrigger was invalid!");
}
// public native void Evaluator::Fire()
public any Native_Evaluator_Fire(Handle plugin, int argc) {
	int evaluator = GetNativeCell(1);
	//check if this thing actually exists
	int at = autoActions.FindValue(evaluator);
	if (at < 0) ThrowNativeError(SP_ERROR_NATIVE, "Evaluator was invalid!");
	FormulaAction action;
	autoActions.GetArray(at, action);
	FireAction(action);
}
// public native void Evaluator::Close()
public any Native_Evaluator_Close(Handle plugin, int argc) {
	int evaluator = GetNativeCell(1);
	if (!RemoveAction(evaluator)) ThrowNativeError(SP_ERROR_NATIVE, "Evaluator was invalid!");
}

// == framework stuff for API

static int generateKey(int trigger) {
	int mask = TriggerToIdBits(trigger);
	int key = GetURandomInt() & ActionMask | mask;
	for (int at=autoActions.FindValue(key),cnt; at>=0; key=((key+1)&ActionMask)|mask, at=autoActions.FindValue(key)) {
		if (++cnt > 1000) ThrowNativeError(SP_ERROR_NATIVE, "Couldn't generate key after 1000 iterations");
	}
	return key;
}

int RegisterTrigger(const char[] name) {
	int tmp;
	if ((tmp=triggerNames.FindString(name))>=0) return tmp; //already registered
	if (triggerNames.Length >= 4096) return -1; //don't want this to be too big
	tmp = triggerNames.PushString(name); //generate new trigger idx
	return tmp;
}
void FireAction(FormulaAction action) {
	float value;
	if (!eval(action.formula,0,_,value) || !setVariable(action.output, value, true)) {
		char name[MAX_NAME_LENGTH], tname[64];
		GetPluginInfo(action.owner, PlInfo_Name, name, sizeof(name));
		triggerNames.GetString(TriggerOfIdBits(action.key), tname, sizeof(tname));
		LogError("Formula exception for %s during %s in %s = %s: %s", name, tname, action.output, action.formula, evalError);
	}
}
bool TriggerAction(int trigger) {
	if (0>trigger>=triggerNames.Length) return false; //trigger has no associated name
	int trig = TriggerToIdBits(trigger);
	FormulaAction action;
	for (int i;i<autoActions.Length;i++) {
		autoActions.GetArray(i, action);
		if ((action.key & TriggerMask) == trig)
			FireAction(action);
	}
	return true;
}
int CreateAction(Handle owner=INVALID_HANDLE, int trigger, const char[] output, const char[] formula, eFormulaSource source=FSource_Plugin) {
	if (0>trigger>=triggerNames.Length) return -1; //trigger has no associated name
	if (autoActions.Length>=ActionMask) return -2; //can't store more actions
	FormulaAction action;
	action.key = generateKey(trigger);
	action.source = source;
	action.owner = owner;
	strcopy(action.output, sizeof(FormulaAction::output), output);
	strcopy(action.formula, sizeof(FormulaAction::formula), formula);
	autoActions.PushArray(action);
	return action.key;
}
bool RemoveAction(int action) {
	int tmp = autoActions.FindValue(action);
	if (tmp<0) return false;
	autoActions.Erase(tmp);
	return true;
}

Action NotifyVariableChanged(const char[] name, float& value) {
	float tmp = value;
	Action result;
	Call_StartForward(fwdVariableChanged);
	Call_PushString(name);
	Call_PushFloatRef(value);
	Call_Finish(result);
	if (result == Plugin_Changed) value = tmp;
	return result;
}
void NotifyVariableChangedPost(const char[] name, float value) {
	Call_StartForward(fwdVariableChangedPost);
	Call_PushString(name);
	Call_PushFloat(value);
	Call_Finish();
}
