#if !defined __formula
#error Not compiling from main file!
#endif
#if defined __formula_api
#endinput
#endif
#define __formula_api

//keep the signum bit free to signal errors
#define TriggerToIdBits(%1) (((%1)&0x07ff)<<20)
#define TriggerOfIdBits(%1) (((%1)>>20)&0x07ff)
#define ActionMask 0x000fffff
#define TriggerMask 0x7ff00000
#define MAX_TRIGGERS 0x800
#define MAX_ACTIONS 0x100000
#define MAX_FILTERS 2048

enum eFormulaSource {
	FSource_Any=-1,
	FSource_Plugin,
	FSource_Config,
}

enum struct FormulaAction {
	int key; //trigger id & action pseudo
	eFormulaSource source;
	Handle owner; //for error printing
	int sourceConfigName; //into config name list, for error printing and to prevent double loading
	int filter;
	char output[MAX_OUTPUT_LENGTH];
	char formula[MAX_FORMULA_LENGTH];
}
static ArrayList triggerNames;
static ArrayList autoActions;
static ArrayList autoFilters;
ArrayList sourceConfigNames;

GlobalForward fwdVariableChanged;
GlobalForward fwdTriggerDropped;

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
	if (sourceConfigNames == null)
		sourceConfigNames = new ArrayList(ByteCountToCells(128));
	else
		sourceConfigNames.Clear();
	if (fwdVariableChanged == null)
		fwdVariableChanged = new GlobalForward("OnFormulaVariableChanged", ET_Ignore, Param_String, Param_Float, Param_Cell);
	if (fwdTriggerDropped == null)
		fwdTriggerDropped = new GlobalForward("OnFormulaTriggerDropped", ET_Ignore, Param_Cell, Param_String);
}

void __removeConfigActions() {
	int c,d,t;
	for (int i=autoActions.Length-1;i>=0;i--) {
		if (autoActions.Get(i,FormulaAction::source)==FSource_Config) {
			autoActions.Erase(i);
			c++;
		}
	}
	d = autoFilters.Length;
	autoFilters.Clear();
	sourceConfigNames.Clear();
	for (int i=triggerNames.Length-1;i>=0;i-=1) {
		if (DropTrigger(i, FSource_Config)) t++;
	}
	if (t)
		PrintToServer("Dropped %i Actions and %i Filters, clearing %i Triggers", c, d, t);
	else
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
	CreateNative("MathTrigger.GetEvaluators", Native_MathTrigger_GetEvaluators);
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
	int asClient = 0;
	if (argc>2) asClient = GetNativeCell(3);
	//validate name
	checkWordChars(varname, 1);
	float value = view_as<float>(GetNativeCell(2));
	setVariable(varname, value, false, asClient);
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
	int asClient = 0;
	if (argc>2) asClient = GetNativeCell(3);
	//validate name
	checkWordChars(varname, 1);
	float value;
	if (getVariable(varname, value, asClient)) {
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
	int evaluator = CreateAction(plugin, trigger, output, formula, _, -1);
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
// public native void MathTrigger::GetEvaluators(Handle plugin=INVALID_HANDLE, ArrayList evaluators=null)
public any Native_MathTrigger_GetEvaluators(Handle plugin, int argc) {
	int trigger = GetNativeCell(1);
	Handle pluginSource = view_as<Handle>(GetNativeCell(2));
	if (pluginSource == INVALID_HANDLE) pluginSource = plugin;
	ArrayList collection = view_as<ArrayList>(GetNativeCell(3));
	int count, action;
	int trigmask = TriggerToIdBits(trigger);
	for (int i;i<autoActions.Length;i++) {
		if (((action=autoActions.Get(i,FormulaAction::key))&trigmask)==trigmask &&
			autoActions.Get(i,FormulaAction::source)==FSource_Plugin &&
			autoActions.Get(i,FormulaAction::owner)==pluginSource) {
			collection.Push(action);
			count++;
		}
	}
}
// public native void Evaluator::Fire()
public any Native_Evaluator_Fire(Handle plugin, int argc) {
	int evaluator = GetNativeCell(1);
	if (!FireActionByKey(evaluator))
		ThrowNativeError(SP_ERROR_NATIVE, "Evaluator was invalid!");
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
	if ((tmp=triggerNames.FindString(""))>=0) { //replace a dropped trigger
		triggerNames.SetString(tmp, name);
	} else {
		if (triggerNames.Length >= MAX_TRIGGERS) return -1; //don't want this to be too big
		tmp = triggerNames.PushString(name); //generate new trigger idx
	}
	return tmp;
}
bool FireActionByKey(int key) {
	//check if this thing actually exists
	int at = autoActions.FindValue(key);
	if (at < 0) return false;
	FormulaAction action;
	autoActions.GetArray(at, action);
	FireAction(action);
	return true;
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
		ParseMathString(action.formula, buffer, sizeof(buffer));
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
	for (int index; index < autoActions.Length; index+=1) {
		autoActions.GetArray(index, action);
		if ((action.key & TriggerMask) == trig)
			FireAction(action);
	}
	return true;
}
//int GetTriggerActionCount(int trigger, eFormulaSource source=FSource_Any) {
//	if (0>trigger>=triggerNames.Length) return 0;
//	int trig = TriggerToIdBits(trigger);
//	int count;
//	FormulaAction action;
//	for (int index; index < autoActions.Length; index+=1) {
//		autoActions.GetArray(index,action);
//		if ((action.key & TriggerMask) == trig) {
//			if (source == FSource_Any || action.source == source) 
//				count += 1;
//		}
//	}
//	return count;
//}
/** removes actions from a trigger and drops the trigger if no actions remain
 * @dropActions - can be used to limit the source for actions to be removed
 * @sourceFileIndex - only consider this config file if dropActions is FSource_Config or -1 for all configs
 * @return true if the action was dropped
 */
bool DropTrigger(int trigger, eFormulaSource dropActions=FSource_Any, int sourceFileIndex=-1) {
	if (0>trigger>=triggerNames.Length) return false; //trigger has no associated name
	int trig = TriggerToIdBits(trigger);
	FormulaAction action;
	bool actionsRemain;
	//remove all remaining actions as specified by the filters
	for (int index=autoActions.Length-1; index >= 0; index-=1) {
		autoActions.GetArray(index, action);
		if ((action.key & TriggerMask) == trig) {
			if (dropActions == FSource_Config && action.source == FSource_Config) {
				if (sourceFileIndex<0 || sourceFileIndex == action.sourceConfigName)
					RemoveAction(action.key);
				else
					actionsRemain = true;
			} else if (dropActions == FSource_Any || action.source == dropActions)
				RemoveAction(action.key);
			else
				actionsRemain = true;
		}
	}
	if (actionsRemain) return false; //can't drop trigger, it still has actions
	if (trigger == trig_map || trigger == trig_conf || trigger == trig_round
	|| trigger == trig_join || trigger == trig_part || trigger == trig_spawn
	|| trigger == trig_part || trigger == trig_time) {
		return true; //never really remove default triggers, just pretend
	}
	char triggerName[MAX_TRIGGERNAME_LENGTH];
	triggerNames.GetString(trigger, triggerName, sizeof(triggerName));
	triggerNames.SetString(trigger,"");
	//we can't really move triggers around, so erasing an entry in the middle of the list is not an option
	char buffer[4];
	for(int index=triggerNames.Length-1; index >= 0; index-=1) {
		triggerNames.GetString(index, buffer, sizeof(buffer));
		if (buffer[0]!=0) //check for empty string
			break;
		//erase dropped triggers from the end, as they do not have any remaining actions
		triggerNames.Erase(index);
	}
	//handle mod event triggers
	if (StrContains(triggerName,"event:")==0) {
		//unhook this dynamic trigger
		UnhookEvent(triggerName[6], OnModEvent);
		trig_events.SetValue(triggerName[6], 0);
	}
	//notify, as dependend plugins might have to update triggers
	Call_StartForward(fwdTriggerDropped);
	Call_PushCell(trigger);
	Call_PushString(triggerName);
	Call_Finish();
	return true;
}
int CreateAction(Handle owner=INVALID_HANDLE, int trigger, const char[] output, const char[] formula, int filter=-1, int sourceFile=-1) {
	if (0>trigger>=triggerNames.Length) return -1; //trigger has no associated name
	if (autoActions.Length>MAX_ACTIONS) return -2; //can't store more actions
	FormulaAction action;
	action.key = generateKey(trigger);
	action.source = (sourceFile == -1) ? FSource_Plugin : FSource_Config;
	action.owner = owner;
	action.sourceConfigName = sourceFile;
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

void NotifyVariableChanged(const char[] name, float value, int owner) {
	Call_StartForward(fwdVariableChanged);
	Call_PushString(name);
	Call_PushFloat(value);
	Call_PushCell(owner);
	Call_Finish();
}

// == Utils for parsing complexer strings with formulas and variables

// allows expressions wrapped in # to be evaludated. ## is the scape for # characters outside of math expressions
// it's a bit like latex $math$, but i already used $ as user variable prefix
// asClient controlls cvar access, 0 = server, -1 = blocked
bool ParseMathString(const char[] raw, char[] out, int maxsize, int asClient=0) {
	int end = strlen(raw); if (maxsize <= end) end = maxsize-1; //comparing string len to buffer len, keep 1 space for \0
	int c, from, len;
	char buffer[MAX_FORMULA_LENGTH];
	char[] outbuf = new char[maxsize]; // guaranteed zero-ed
	bool inMathContext;
	for (;c<end;c++) {
		if (raw[c] == '#') {
			//collect chars to next marker
			len = c-from+1; //to = c (exclusive) -> len = to-from (+1 for \0)
			if (len > sizeof(buffer)) len = sizeof(buffer); //do not exceed buffer size
			strcopy(buffer, len, raw[from]);
			from = c+1; //move from post # for next part
			//if we were in math context, eval and replace buffer
			if (inMathContext) {
				float value;
				if (!eval(buffer, _, _, value, asClient)) return false;
				if (FloatFraction(value) < 0.000001) {
					Format(buffer, sizeof(buffer), "%i", RoundToZero(value));
				} else {
					Format(buffer, sizeof(buffer), "%f", value);
				}
			}
			//append buffer and switch context
			StrCat(outbuf, maxsize, buffer);
			//chekc for ##
			if (raw[c+1] == '#' && !inMathContext) {
//				StrCat(outbuf, maxsize, "#");
				c++;
			} else {
				inMathContext =! inMathContext;
			}
		}
	}
	if (inMathContext) return PutError2(false, "Math context starting at %i not terminated", from);
	if (from<end) { //copy tail
		len = end-from+1; //+1 for \0
		strcopy(buffer, len, raw[from]);
		StrCat(outbuf, maxsize, buffer);
	}
	strcopy(out, maxsize, outbuf);
	return true;
}

// == Config Utilities

static void LoadFromKeyValues(KeyValues kv, ArrayList newActions=null, int sourceFileIndex) {
	char name[MAX_FORMULA_LENGTH], value[MAX_FORMULA_LENGTH];
	int triggerId;
	if (kv.GotoFirstSubKey()) do {
		kv.GetSectionName(name, sizeof(name));
		triggerId = triggerNames.FindString(name);
		if (triggerId < 0) {
			triggerId = GetModEventTrigger(name);
			if (triggerId < 0) continue; //not a mod event trigger either
		}
		
		if (kv.GotoFirstSubKey(false)) {
//			PrintToServer("Trigger %s:",name);
			do {
				//traverse triggers
				kv.GetSectionName(name, sizeof(name));
				bool section = kv.GetDataType(NULL_STRING)==KvData_None;
				bool isFilter = StrEqual(name, "filter", false);
				if (!section && !isFilter) {
					//parse unfiltered actions
					int action;
					kv.GetString(NULL_STRING, value, sizeof(value));
					if ((action=CreateAction(_, triggerId, name, value, _, sourceFileIndex))>=0) {
//						PrintToServer(" %08X %s = %s",action,name,value);
						if (newActions!=null) newActions.Push(action);
					}
				} else if (section && isFilter) {
					//parse blocks of "filter fule" { actions }
					char filter[256]; int fidx;
					if (kv.GotoFirstSubKey()) do {
						kv.GetSectionName(filter, sizeof(filter));
						fidx = CreateFilter(filter);
						//parse filtered actions
						if (kv.GotoFirstSubKey(false)) do {
							kv.GetSectionName(name, sizeof(name));
							section = kv.GetDataType(NULL_STRING)==KvData_None;
							if (!section) {
								int action;
								kv.GetString(NULL_STRING, value, sizeof(value));
								if ((action=CreateAction(_, triggerId, name, value, fidx, sourceFileIndex))>=0) {
//									PrintToServer(" %08X %s = %s if: %s",action,name,value,filter);
									if (newActions!=null) newActions.Push(action);
								}
							}
						} while (kv.GotoNextKey(false));
						kv.GoBack();
					} while (kv.GotoNextKey());
					kv.GoBack();
				}
				//ideas for formulating sections:
				// - filters to conditionally trigger
				// - maybe let it run commands conditionally?
				
			} while (kv.GotoNextKey(false));
		}
		kv.GoBack();
	} while (kv.GotoNextKey());
}

bool LoadConfigByName(const char[] name, bool triggerLoad=false) {
	int sourceIdx = sourceConfigNames.FindString(name);
	if (sourceIdx < 0) sourceIdx = sourceConfigNames.PushString(name);
	else if (countActionsFromConfig(sourceIdx)>0) return false;
	
	char path[PLATFORM_MAX_PATH], name2[128];
	KeyValues kv;
	ArrayList actions = null;
	if (triggerLoad) actions = new ArrayList();
	
	strcopy(name2, sizeof(name2), name);
	ReplaceString(name2, sizeof(name2), "..", "xx"); //don't give opportunity to traverse up
	BuildPath(Path_SM, path, sizeof(path), "configs/formula/%s.cfg", name2);
	if (!FileExists(path)) return false;
	kv = new KeyValues("formula");
	kv.ImportFromFile(path);
	
	LoadFromKeyValues(kv, actions, sourceIdx);
	delete kv;
	
	if (triggerLoad) {
		int tclmask = TriggerToIdBits(trig_conf);
		for (int aidx;aidx<actions.Length;aidx++) {
			int akey = actions.Get(aidx);
			if ((akey & TriggerMask)==tclmask) {
				FireActionByKey(akey);
			}
		}
	}
	delete actions;
	return true;
}
int UnloadConfigByName(const char[] name) {
	int source = sourceConfigNames.FindString(name);
	if (source < 0) return 0;
	int z;
	for (int i=autoActions.Length-1;i>=0;i-=1) {
		if (autoActions.Get(i,FormulaAction::sourceConfigName) == source) {
			RemoveAction(autoActions.Get(i,FormulaAction::key));
			z++;
		}
	}
	for (int i=triggerNames.Length-1;i>=0;i-=1) {
		DropTrigger(i, FSource_Config, source);
	}
	return z;
}
int countActionsFromConfig(int source) {
	int z;
	for (int i;i<autoActions.Length;i++) {
		if (autoActions.Get(i,FormulaAction::sourceConfigName) == source) z++;
	}
	return z;
}
void ReloadConfigs() {
	//reset auto actions
	__removeConfigActions();
	
	char mapname[PLATFORM_MAX_PATH];
	GetCurrentMap(mapname, sizeof(mapname));
	
	LoadConfigByName("default");
	
	LoadConfigByName(mapname);
	
	//notify default triggers to fire OnMapStart so user vars can init
	TriggerAction(trig_conf);
}

void PrintListToConsole(int client) {
	char name[128];
	int actions;
	PrintToConsole(client, "All %i known configs:", sourceConfigNames.Length);
	for (int i;i<sourceConfigNames.Length;i++) {
		sourceConfigNames.GetString(i, name, sizeof(name));
		if ((actions=countActionsFromConfig(i))>0) {
			PrintToConsole(client, " %2i %s: %i actions", i, name, actions);
		} else {
			PrintToConsole(client, " %2i %s: UNLOADED", i, name);
		}
	}
}

