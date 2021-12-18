#if !defined __formula
#error Not compiling from main file!
#endif
#if defined __formula_stdtrigger
#endinput
#endif
#define __formula_stdtrigger

void __stdtrigger_init() {
	trig_map   = RegisterTrigger("OnMapStart");
	trig_conf  = RegisterTrigger("OnFormulasReloaded");
	trig_round = RegisterTrigger("OnRoundStart");
	trig_join  = RegisterTrigger("OnPlayerJoined");
	trig_part  = RegisterTrigger("OnPlayerParted");
	trig_spawn = RegisterTrigger("OnPlayerSpawn");
	trig_death = RegisterTrigger("OnPlayerDeath");
	trig_time  = RegisterTrigger("EveryMinute");
	
	HookEvent("teamplay_round_start", onRoundStart);
	HookEvent("player_death", onPlayerDeath);
}

public void OnConfigsExecuted() {
	CreateTimer(60.0, timerMinute, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	UpdateEntityCount();
	//don't actually use map start as configs are still busy there
	TriggerAction(trig_map);
}

public void OnClientConnected(int client) {
	TriggerAction(trig_join);
}
public void OnClientDisconnect_Post(int client) {
	TriggerAction(trig_part);
}

public void onRoundStart(Event event, const char[] name, bool dontBroadcast) {
	TriggerAction(trig_round);
}

void hookPlayerEntity(int client) {
	SDKHook(client, SDKHook_SpawnPost, onClientSpawn);
	SDKHook(client, SDKHook_OnTakeDamagePost, onClientDamagedPost);
}
static bool updatingEntityCount;
static void UpdateEntityCount() {
	setVariable("$edicts", float(GetEntityCount()), true);
	updatingEntityCount=false;
}
public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "player")) {
		hookPlayerEntity(entity);
	}
	UpdateEntityCount();
}
public void OnEntityDestroyed(int entity) {
	//Entities stay alive/valid for the rest of the tick
	if (updatingEntityCount) return;
	updatingEntityCount = true;
	RequestFrame(UpdateEntityCount);
}

static bool clientDeathHandled[MAXPLAYERS+1];
void onClientSpawn(int client) {
	TriggerAction(trig_spawn);
	clientDeathHandled[client]=false;
}
static void handleDeath(int client) {
	if (clientDeathHandled[client]) return;
	TriggerAction(trig_death);
	clientDeathHandled[client]=true;
}
public void onPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	handleDeath(GetClientOfUserId(event.GetInt("userid")));
}
void onClientDamagedPost(int victim, int attacker, int inflictor, float damage, int damagetype) {
	if(GetClientHealth(victim) <= 0) {
		handleDeath(victim);
	}
}

public Action timerMinute(Handle timer) {
	TriggerAction(trig_time);
}
