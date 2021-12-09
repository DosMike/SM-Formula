#include <commandfilters>
#include <sdkhooks>
#include <keyvalues>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "21w49a"

public Plugin myinfo = {
	name = "Formula",
	author = "reBane",
	description = "Have some calc action with cvars",
	version = PLUGIN_VERSION,
	url = "N/A"
}

#include "mathcore.sp"
#include "formulaApi.sp"
#include "stdtrigger.sp"

public void OnPluginStart() {
	__mathcore_init();
	__api_init();
	__stdtrigger_init();
	RegConsoleCmd("sm_eval", CommandEval, "Evaluate math expressions with ConVars, targets and variables");
	RegConsoleCmd("sm_calc", CommandEval, "Evaluate math expressions with ConVars, targets and variables");
	RegAdminCmd("sm_assign", CommandAssign, ADMFLAG_RCON, "<target> <formula> - Manually compute and assign a value to target");
	RegAdminCmd("sm_formula", CommandAssign, ADMFLAG_RCON, "<target> <formula> - Manually compute and assign a value to target");
	RegAdminCmd("sm_formula_reload", CommandReload, ADMFLAG_RCON, "Reload configs (keeps current values)");
	
	for (int i=1;i<=MaxClients;i++) {
		if (IsClientConnected(i)) {
			hookPlayerEntity(i);
		}
	}
}

bool hasAdminFlag(int client, int flags) {
	if (!client) return true;
	AdminId admin = GetUserAdmin(client);
	return (admin != INVALID_ADMIN_ID) && (admin.GetFlags(Access_Effective)&flags)==flags;
}

public Action CommandEval(int client, int args) {
	char f[256];
	GetCmdArgString(f, sizeof(f));
	float result;
	bool success = eval(f,_,_,result, hasAdminFlag(client, ADMFLAG_RCON));

	if (GetCmdReplySource() == SM_REPLY_TO_CHAT) {
		ReplyToCommand(client, "\x01\x07A9A9A9%s =", f);
		if (success) {
			ReplyToCommand(client, "\x01\x074B9664> \x0798FB98%f", result);
		} else
			ReplyToCommand(client, "\x01\x07FF4040E: \x07FFA9A9%s", evalError);
	} else {
		if (success) {
			ReplyToCommand(client, "> %f", result);
		} else
			ReplyToCommand(client, "Error: %s", evalError);
	}
	return Plugin_Handled;
}

public Action CommandAssign(int client, int args) {
	char f[256];
	char varname[128];
	GetCmdArg(1, varname, sizeof(varname));
	GetCmdArg(2, f, sizeof(f));
	float result;
	bool success = eval(f,_,_,result) && setVariable(varname, result, true);
	
	if (GetCmdReplySource() == SM_REPLY_TO_CHAT) {
		ReplyToCommand(client, "\x01\x07A9A9A9F %s", f);
		if (success) {
			ReplyToCommand(client, "\x01\x074B9664> \x0798FB98%s := %f", varname, result);
		} else
			ReplyToCommand(client, "\x01\x07FF4040E: \x07FFA9A9%s", evalError);
	} else {
		if (success) {
			ReplyToCommand(client, "> %s := %f", varname, result);
		} else
			ReplyToCommand(client, "Error: %s", evalError);
	}
	return Plugin_Handled;
}

public Action CommandReload(int client, int args) {
	ReloadConfigs();
	if (GetCmdReplySource()==SM_REPLY_TO_CHAT)
		ReplyToCommand(client, "\x01\x0798FB98Formulas reloaded from config");
	else
		ReplyToCommand(client, "Formulas reloaded from config");
	return Plugin_Handled;
}

static void LoadFromConfig(KeyValues kv) {
	char name[128], value[512];
	int at;
	if (kv.GotoFirstSubKey()) do {
		kv.GetSectionName(name, sizeof(name));
		at = triggerNames.FindString(name);
		if (at < 0) continue;
		
		if (kv.GotoFirstSubKey(false)) {
			PrintToServer("Trigger %s:",name);
			do {
				kv.GetSectionName(name, sizeof(name));
				bool section = kv.GetDataType(NULL_STRING)==KvData_None;
				if (!section) {
					int action;
					kv.GetString(NULL_STRING, value, sizeof(value));
					if ((action=CreateAction(_, at, name, value, FSource_Config))>=0)
						PrintToServer(" %4i  %s = %s",action,name,value);
				}
				//ideas for formulating sections:
				// - filters to conditionally trigger
				// - maybe let it run commands conditionally?
				
			} while (kv.GotoNextKey(false));
		}
		kv.GoBack();
	} while (kv.GotoNextKey());
}

public void OnMapStart() {
	ReloadConfigs();
}
public void ReloadConfigs() {
	//reset auto actions
	__removeConfigActions();
	
	char mapname[PLATFORM_MAX_PATH];
	GetCurrentMap(mapname, sizeof(mapname));
	char path[PLATFORM_MAX_PATH];
	KeyValues kv;
	
	BuildPath(Path_SM, path, sizeof(path), "configs/formula/default.cfg");
	kv = new KeyValues("formula");
	kv.ImportFromFile(path);
	LoadFromConfig(kv);
	delete kv;
	
	BuildPath(Path_SM, path, sizeof(path), "configs/formula/%s.cfg", mapname);
	kv = new KeyValues("formula");
	kv.ImportFromFile(path);
	LoadFromConfig(kv);
	delete kv;
	
	//notify default triggers to fire OnMapStart so user vars can init
	TriggerAction(trig_conf);
}