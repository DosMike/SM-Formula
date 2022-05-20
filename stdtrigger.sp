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
	
	//preparing the string map for mod events
	if (trig_events == null)
		trig_events = new StringMap();
	else
		trig_events.Clear();
	
	//read all events from file into the map, but don't register them until needed
	KeyValues events = new KeyValues("ModEvents");
	events.ImportFromFile("resource/modevents.res");
	events.GotoFirstSubKey();
	char name[64];
	int eventCounter;
	do {
		events.GetSectionName(name, sizeof(name));
		eventCounter+=1;
		trig_events.SetValue(name, 0);
	} while (events.GotoNextKey());
	delete events;
	PrintToServer("[Formula] Found %i Mod Events", eventCounter);
	
	//now legacy: hook and bind these two events to the mod event list
	HookEvent("teamplay_round_start", onRoundStart);
	HookEvent("player_death", onPlayerDeath);
	trig_events.SetValue("teamplay_round_start", trig_round);
	trig_events.SetValue("player_death", trig_death);
}

/** 
 * @param eventName requires the format event:modeventname
 * @return -1 if mod event does not exist or name is invalid, trigger id otherwise
 */
int GetModEventTrigger(const char[] eventName) {
	if (StrContains(eventName, "event:")!=0)
		return -1;
	//trigger starts with event: - check if this is a mod event we know
	int triggerId=-1;
	if (!trig_events.GetValue(eventName[6],triggerId) || triggerId<0)
		//can't trigger on unknown mod events
		return -1;
	//mod knows this event
	if (triggerId == 0) {
		//not yet hooked
		//register with event: prefix, sure
		triggerId = RegisterTrigger(eventName);
		//this should never have to replace:
		trig_events.SetValue(eventName[6],triggerId);
		//hook the event
		HookEvent(eventName[6], OnModEvent);
	}
	return triggerId;
}
///**
// * Drops and unregisters a mod event trigger if unused.
// * @param eventName requires the format event:modeventname
// */
//void CheckModEventTrigger(const char[] eventName) {
//	if (StrContains(eventName, "event:")!=0)
//		return;
//	int triggerId=-1;
//	if (!trig_events.GetValue(eventName[6],triggerId) || triggerId<0)
//		return;
//	if (GetTriggerActionCount(triggerId)==0)
//		DropTrigger(triggerId);
//}
public void OnModEvent(Event event, const char[] name, bool dontBroadcast) {
	int triggerId=-1;
	if (trig_events.GetValue(name,triggerId) && triggerId>0)
		TriggerAction(triggerId);
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
