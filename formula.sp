//prevent compiling sub-scripts
#define __formula

#include <commandfilters>
#include <sdkhooks>
#include <keyvalues>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "21w50b"

#define MAX_FORMULA_LENGTH 512
#define MAX_OUTPUT_LENGTH 128
#define MAX_TRIGGERNAME_LENGTH 128
#define MAX_FILTER_LENGTH 256

public Plugin myinfo = {
	name = "Formula",
	author = "reBane",
	description = "Have some calc action with cvars",
	version = PLUGIN_VERSION,
	url = "N/A"
}

//global trigger ids in canse we need them
int trig_map;
int trig_conf;
int trig_round;
int trig_join;
int trig_part;
int trig_spawn;
int trig_death;
int trig_time;

#include "mathcore.sp"
#include "formulaApi.sp"
#include "stdtrigger.sp"

public void OnPluginStart() {
	__mathcore_init();
	__api_init();
	__stdtrigger_init();
	RegConsoleCmd("sm_eval", CommandEval, "Evaluate math expressions with ConVars, targets and variables");
	RegConsoleCmd("sm_calc", CommandEval, "Evaluate math expressions with ConVars, targets and variables");
	RegConsoleCmd("sm_mathexec", CommandMathExec, "Run the argument as command with expressions in # evaluated");
	RegConsoleCmd("sm_mexec", CommandMathExec, "Run the argument as command with expressions in # evaluated");
	RegAdminCmd("sm_assign", CommandAssign, ADMFLAG_RCON, "<target> <formula> - Manually compute and assign a value to target");
	RegAdminCmd("sm_formula", CommandAssign, ADMFLAG_RCON, "<target> <formula> - Manually compute and assign a value to target");
	RegAdminCmd("sm_formula_list", CommandList, ADMFLAG_CONFIG, "List configs loaded in console");
	RegAdminCmd("sm_formula_load", CommandLoadManual, ADMFLAG_CONFIG, "Manually load a config by name. Reload or map change will drop it again");
	RegAdminCmd("sm_formula_reload", CommandReload, ADMFLAG_CONFIG, "Reload configs (keeps current values)");
	RegAdminCmd("sm_formula_unload", CommandUnload, ADMFLAG_CONFIG, "Reload configs (keeps current values)");
	
	for (int i=1;i<=MaxClients;i++) {
		if (IsClientConnected(i)) {
			hookPlayerEntity(i);
		}
	}
}


//similar to basecommands.sp but i can't check the protected list
bool IsClientAllowedToChangeCvar(int client, ConVar cvar) {
	if (client==0) return true;
	bool allowed;
	int clientFlags = GetUserFlagBits(client);
	if (clientFlags & ADMFLAG_ROOT) {
		allowed = true;
	} else if (!(clientFlags & ADMFLAG_CONVARS)) {
		//allowed = false; //default
	} else {
		char cvarname[64];
		cvar.GetName(cvarname, sizeof(cvarname));
		if (cvar.Flags & FCVAR_PROTECTED) {
			allowed = ((clientFlags & ADMFLAG_PASSWORD) == ADMFLAG_PASSWORD);
		} else if (StrEqual(cvarname, "sv_cheats")) {
			allowed = ((clientFlags & ADMFLAG_CHEATS) == ADMFLAG_CHEATS);
		} else if (!(StrEqual(cvarname, "rcon_password")||StrEqual(cvarname, "sm_show_activity")||StrEqual(cvarname, "sm_immunity_mode"))) {
			allowed = true;
		}
	}
	return allowed;
}

public Action CommandEval(int client, int args) {
	char f[MAX_FORMULA_LENGTH];
	GetCmdArgString(f, sizeof(f));
	float result;
	bool success = eval(f,_,_,result, client);

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

public Action CommandMathExec(int client, int args) {
	char f[MAX_FORMULA_LENGTH], g[MAX_FORMULA_LENGTH];
	GetCmdArgString(f, sizeof(f));
	bool success = ParseMathString(f, g, sizeof(g), client);
	
	if (GetCmdReplySource() == SM_REPLY_TO_CHAT) {
		if (!success) {
			ReplyToCommand(client, "\x01\x07A9A9A9> %s", f);
			ReplyToCommand(client, "\x01\x07FF4040E: \x07FFA9A9%s", evalError);
			return Plugin_Handled;
		} else
			ReplyToCommand(client, "\x01\x07A9A9A9> %s", g);
	} else {
		if (!success) {
			ReplyToCommand(client, "> %s", f);
			ReplyToCommand(client, "Error: %s", evalError);
			return Plugin_Handled;
		} else
			ReplyToCommand(client, "> %s", g);
	}
	if (client == 0) ServerCommand("%s", g);
	else FakeClientCommand(client, "%s", g);
	return Plugin_Handled;
}

public Action CommandAssign(int client, int args) {
	char f[MAX_FORMULA_LENGTH];
	char varname[MAX_OUTPUT_LENGTH];
	GetCmdArg(1, varname, sizeof(varname));
	GetCmdArg(2, f, sizeof(f));
	float result;
	bool success = eval(f,_,_,result,client) && setVariable(varname, result, true, client);
	
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

public Action CommandList(int client, int args) {
	PrintListToConsole(client);
	return Plugin_Handled;
}

public Action CommandLoadManual(int client, int args) {
	char name[PLATFORM_MAX_PATH];
	if (GetCmdArgs() == 0) {
		GetCmdArg(0, name, sizeof(name));
		ReplyToCommand(client, "Usage: %s <filename> - Load a formula config form the configs directory", name);
		return Plugin_Handled;
	}
	GetCmdArgString(name, sizeof(name));
	int source;
	if ((source=sourceConfigNames.FindString(name))>=0 && countActionsFromConfig(source)>0) {
		ReplyToCommand(client, "The config '%s' was already loaded", name);
	} else if (!LoadConfigByName(name, true)) {
		ReplyToCommand(client, "The config '%s' does not exist", name);
	} else {
		ReplyToCommand(client, "Formulas loaded config '%s'", name);
	}
	return Plugin_Handled;
}
public Action CommandUnload(int client, int args) {
	if (GetCmdArgs()==0) {
		__removeConfigActions();
		ReplyToCommand(client, "Formulas unloaded all configs");
	} else {
		char name[128];
		GetCmdArgString(name, sizeof(name));
		int removed;
		if ((removed=UnloadConfigByName(name))==0) {
			ReplyToCommand(client, "The config '%s' was not loaded", name);
		} else {
			ReplyToCommand(client, "Formulas unloaded config '%s' with %i actions", name, removed);
		}
	}
	return Plugin_Handled;
}
public Action CommandReload(int client, int args) {
	if (GetCmdArgs()==0) {
		ReloadConfigs();
		ReplyToCommand(client, "Formulas reloaded from config");
	} else {
		char name[128];
		GetCmdArgString(name, sizeof(name));
		int removed=UnloadConfigByName(name);
		if (removed>0) {
			ReplyToCommand(client, "Removed %i actions from '%s' before reloading", removed, name);
			LoadConfigByName(name, true);
		} else {
			ReplyToCommand(client, "The config '%s' was not loaded, try loading it", name);
		}
	}
	return Plugin_Handled;
}

public void OnMapStart() {
	ReloadConfigs();
}