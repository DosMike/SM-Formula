#if defined __formula_api
#endinput
#endif
#define __formula_api

#define TriggerToIdBits(%1) (((%1)&0x0fff)<<20)
#define TriggerOfIdBits(%1) (((%1)>>20)&0x0fff)
#define ActionMask 0x000fffff
#define TriggerMask 0xfff00000
#define MAX_TRIGGERS 0x1000
#define MAX_ACTIONS 0x100000
#define MAX_FILTERS 2048

enum eFormulaSource {
	FSource_Plugin,
	FSource_Config,
}

enum struct FormulaAction {
	int key; //trigger id & action pseudo
	eFormulaSource source;
	int filter;
	Handle owner; //for error printing
	char output[MAX_OUTPUT_LENGTH];
	char formula[MAX_FORMULA_LENGTH];
}
ArrayList triggerNames;
static ArrayList autoActions;
ArrayList autoFilters;
static Regex varFormat;

GlobalForward fwdVariableChanged;

void __api_init() {
	if (triggerNames == null) triggerNames = new ArrayList(ByteCountToCells(MAX_TRIGGERNAME_LENGTH));
	if (autoActions == null)
		autoActions = new ArrayList(sizeof(FormulaAction));
	else
		autoActions.Clear();
	if (autoFilters == null)
		autoFilters = new ArrayList(ByteCountToCells(MAX_FILTER_LENGTH));
	else
		autoFilters.Clear();
	if (fwdVariableChanged == null)
		fwdVariableChanged = new GlobalForward("OnFormulaVariableChanged", ET_Ignore, Param_String, Param_Float);
	if (varFormat == null) {
		char error[512];
		RegexError code;
		varFormat = new Regex("\\b([if][$]\\w+)\\b", PCRE_CASELESS, error, sizeof(error), code);
		if (code != REGEX_ERROR_NONE) {
			PrintToServer("Regex Error %i: %s", code, error);
		}
	}
}

void __removeConfigActions() {
	int c,d;
	for (int i=autoActions.Length-1;i>=0;i--) {
		if (autoActions.Get(i,FormulaAction::source)==FSource_Config) {
			autoActions.Erase(i);
			c++;
		}
	}
	d = autoFilters.Length;
	autoFilters.Clear();
	PrintToServer("Dropped %i Actions and %i Filters", c, d);
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
	CreateNative("Evaluator.SetFilter", Native_Evaluator_SetFilter);
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
	int evaluator = CreateAction(plugin, trigger, output, formula, _, FSource_Plugin);
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
// public native void Evaluator::SetFilter(const char[])
public any Native_Evaluator_SetFilter(Handle plugin, int argc) {
	int evaluator = GetNativeCell(1);
	//get filter
	int filterLen, error, clear;
	char filter[MAX_FILTER_LENGTH];
	if (!(clear = IsNativeParamNullString(2))) {
		if ((error=GetNativeStringLength(2, filterLen))!=SP_ERROR_NONE) ThrowNativeError(error, "Could not get formula");
		GetNativeString(2, filter, sizeof(filter));
	}
	//check if this thing actually exists
	int at = autoActions.FindValue(evaluator);
	if (at < 0) ThrowNativeError(SP_ERROR_NATIVE, "Evaluator was invalid!");
	//do it
	if (clear) {
		int fidx = autoActions.Get(at, FormulaAction::filter);
		autoActions.Set(at, -1, FormulaAction::filter);
		if (GetFilterCount(fidx)<=0) RemoveFilter(fidx); //if no more instances of the filter remain, nuke it
	} else {
		int fidx = CreateFilter(filter);
		if (fidx >= 0) autoActions.Set(at, fidx, FormulaAction::filter);
	}
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
	if (triggerNames.Length >= MAX_TRIGGERS) return -1; //don't want this to be too big
	tmp = triggerNames.PushString(name); //generate new trigger idx
	return tmp;
}
void FireAction(FormulaAction action) {
	float value;
	char name[MAX_NAME_LENGTH];
	char tname[MAX_TRIGGERNAME_LENGTH];
	char buffer[MAX_FORMULA_LENGTH];
	if (action.filter >= 0) {
		autoFilters.GetString(action.filter, buffer, sizeof(buffer));
		if (!eval(buffer, _, _, value)) {
			//filter is broken
			GetPluginInfo(action.owner, PlInfo_Name, name, sizeof(name));
			triggerNames.GetString(TriggerOfIdBits(action.key), tname, sizeof(tname));
			LogError("Formula exception for %s during %s in filter %s for %s = %s: %s", name, tname, buffer, action.output, action.formula, evalError);
		} else if (value <= 0.0) return; //filter failed
	}
	if (StrEqual(action.output,"exec",false)) {
		strcopy(buffer, sizeof(buffer), action.formula);
		ReplaceVarNames(buffer, sizeof(buffer));
		ServerCommand("%s", buffer);
	} else if (!eval(action.formula,0,_,value) || !setVariable(action.output, value, true)) {
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
int CreateAction(Handle owner=INVALID_HANDLE, int trigger, const char[] output, const char[] formula, int filter=-1, eFormulaSource source=FSource_Plugin) {
	if (0>trigger>=triggerNames.Length) return -1; //trigger has no associated name
	if (autoActions.Length>MAX_ACTIONS) return -2; //can't store more actions
	FormulaAction action;
	action.key = generateKey(trigger);
	action.source = source;
	action.owner = owner;
	action.filter = filter;
	strcopy(action.output, sizeof(FormulaAction::output), output);
	strcopy(action.formula, sizeof(FormulaAction::formula), formula);
	autoActions.PushArray(action);
	return action.key;
}
bool RemoveAction(int action) {
	int tmp = autoActions.FindValue(action);
	if (tmp<0) return false;
	int filter = autoActions.Get(tmp, FormulaAction::filter);
	autoActions.Erase(tmp);
	if (filter>=0 && GetFilterCount(filter)<=0) {
		RemoveFilter(filter);
	}
	return true;
}
int CreateFilter(const char[] filter) {
	int at = autoFilters.FindString(filter);
	if (at >= 0) return at;
	if (autoFilters.Length>=MAX_FILTERS) return -1;
	return autoFilters.PushString(filter);
}
void RemoveFilter(int filter) {
	if (filter < 0 || filter >= autoFilters.Length) return;
	autoFilters.Erase(filter);
	//fix left over filters
	for (int i=0;i<autoActions.Length;i++) {
		int f = autoActions.Get(i,FormulaAction::filter);
		if (f==filter) autoActions.Set(i,-1,FormulaAction::filter);
		else if (f>filter) autoActions.Set(i,f-1,FormulaAction::filter); //fitlers moved down one index
	}
}
int GetFilterCount(int filter) {
	int result;
	if (filter >= 0) for (int i=0;i<autoActions.Length;i++) {
		int f = autoActions.Get(i,FormulaAction::filter);
		if (f == filter) result++;
	}
	return result;
}

void NotifyVariableChanged(const char[] name, float value) {
	Call_StartForward(fwdVariableChanged);
	Call_PushString(name);
	Call_PushFloat(value);
	Call_Finish();
}

//using the power of regex, search only for candidate variables
// that actually appear in the buffer, and replace them if set
// logic would be roughly like this, but in pain:
// buffer.replace(/\b[if][$]\w+/, match=>isVariable(match)?getVariable(match):match)
void ReplaceVarNames(char[] buffer, int maxsize) {
	int matches = varFormat.MatchAll(buffer);
	char[] repl = new char[maxsize];
	char capture[MAX_OUTPUT_LENGTH+1];
	char substr[MAX_FORMULA_LENGTH];
	int from,head,clen;
	
	for (int i=0;i<matches;i++) {
		varFormat.GetSubString(0, capture, sizeof(capture), i);
		head = varFormat.MatchOffset(i);
		clen = strlen(capture);
		head -= clen; //why tf is MatchOffset returning the END index?
		
		//append head (pre-match) to output
		if (head>from) {
			int len=head-from+1;//include \0 for copy
			if (len>sizeof(substr)) len = sizeof(substr);
			strcopy(substr, len, buffer[from]);
			StrCat(repl, maxsize, substr);
			from = head;
		}
		
		//append replacement to output
		from += clen; //end of capture for next head
		if (getVariableType(capture[1])==1) {
			float value;
			if (!getVariable(capture[1], value)) {/*dont replace*/}
			else if (capture[0]=='i') {
				Format(capture, sizeof(capture), "%i", RoundToZero(value));
			} else {
				Format(capture, sizeof(capture), "%f", value);
			}
		}
		StrCat(repl, maxsize, capture);
	}
	//tail handling
	if (from < strlen(buffer)) {
		StrCat(repl, maxsize, buffer[from]);
	}
	//copy back
	strcopy(buffer, maxsize, repl);
}
//naive approach, this might be faster for small amounts of
// variables, but iterating over every varibale will be slow
// if a bunch are defined
//void ReplaceVarNames(char[] buffer, int maxsize) {
//	static RegEx
//	char key[MAX_OUTPUT_LENGTH+1];
//	char rep[32];
//	float value;
//	StringMapSnapshot snap = varValues.Snapshot();
//	for (int i=0;i<snap.Length;i++) {
//		snap.GetKey(i,key[1],sizeof(key)-1);
//		if (!varValues.GetValue(key[1], value)) continue;
//		key[0]='f';
//		Format(rep, sizeof(rep), "%f", value);
//		ReplaceString(buffer, maxsize, key, rep, false);
//		key[0]='i';
//		Format(rep, sizeof(rep), "%i", RoundToZero(value));
//		ReplaceString(buffer, maxsize, key, rep, false);
//	}
//	delete snap;
//}
