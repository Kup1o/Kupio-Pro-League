#pragma semicolon 1
#pragma tabsize 0

#define DEBUG

#define PLUGIN_AUTHOR "Kupio & X@IDER & ofir753 & Niveh & Antithasys & Leonardo & splewis"
#define PLUGIN_VERSION "3.0.1"
#define NONE 0
#define SPEC 1
#define TEAM1 2
#define TEAM2 3
#define MAX_ID 32
#define MAX_CLIENTS 129
#define MAX_NAME 96
#define GAME_UNKNOWN 0
#define GAME_CSTRIKE 1
#define WARMUP 1
#define KNIFE_ROUND 2
#define MATCH 3
#define COMPETITIVE 1
#define WINGMAN 2
#define CONFRONTATION 3 // 1v1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

EngineVersion g_Game;

public Plugin myinfo = 
{
	name = "[Kupio Pro League] Core", 
	author = PLUGIN_AUTHOR, 
	description = "Match Manager", 
	version = PLUGIN_VERSION, 
	url = "https://kaliento.ru"
};

ConVar SetMaxPausesPerTeamKPL = null;
ConVar RequiredReadyPlayers = null;
Handle hSetModel = INVALID_HANDLE;
Handle hDrop = INVALID_HANDLE;
Handle PlayersReadyList;
Handle gh_SilentPrefixes = INVALID_HANDLE;
Handle gh_Prefixes = INVALID_HANDLE;
char gs_Prefixes[32];
char gs_SilentPrefixes[32];
char MessageFormat[512] = " \x04[Kupio Pro League] To: [{DMG_TO} / {HITS_TO} hits] From: [{DMG_FROM} / {HITS_FROM} hits] - {NAME} ({HEALTH} hp)";
char ChatPrefix0[50] = " \x04[Kupio Pro League]"; // info in chat
char ChatPrefix1[50] = " \x0F[Kupio Pro League]"; // errors in chat
char ChatPrefix2[50] = "[Kupio Pro League]"; // info in console
char ClientSteamID[32];
bool TacticUnpauseCT;
bool g_bLog = false;
bool TacticUnpauseT;
bool StayUsed;
bool UnpauseLock;
bool SwitchUsed;
bool TeamsWereSwapped;
bool ManualCaptain;
bool CaptainsSelected;
bool CaptainMenu;
bool ReadyLock;
int CurrentRound;
int ReadyPlayers;
int CaptainCT;
int CaptainT;
int Damage[MAXPLAYERS + 1][MAXPLAYERS + 1];
int Hits[MAXPLAYERS + 1][MAXPLAYERS + 1];
char CaptainID_CT[40];
char CaptainID_T[40];
char ClientCheck[40];
char TeamName_T[64];
char TeamName_CT[64];
char CaptainName_T[64];
char CaptainName_CT[64];
char selected_player_global[40];
char selected_player_global_exchange[40];
char selected_player_global_exchange_with[40];
int MoneyOffset;
int RoundsWon_T;
int RoundsWon_CT;
int team_t;
int team_ct;
int WinningTeam;
int KRWinner;
int TotalPausesCT;
int TotalPausesT;
int MaxPausesCT;
int MaxPausesT;
int game = GAME_UNKNOWN;


char teams[4][16] = 
{
	"N/A", 
	"SPEC", 
	"T", 
	"CT"
};

char t_models[4][PLATFORM_MAX_PATH] = 
{
	"models/player/t_phoenix.mdl", 
	"models/player/t_leet.mdl", 
	"models/player/t_arctic.mdl", 
	"models/player/t_guerilla.mdl"
};

char ct_models[4][PLATFORM_MAX_PATH] = 
{
	"models/player/ct_urban.mdl", 
	"models/player/ct_gsg9.mdl", 
	"models/player/ct_sas.mdl", 
	"models/player/ct_gign.mdl"
};

DropWeapon(client, ent)
{
	if (hDrop != INVALID_HANDLE)
		SDKCall(hDrop, client, ent, 0, 0);
	else
	{
		char edict[MAX_NAME];
		GetEdictClassname(ent, edict, sizeof(edict));
		FakeClientCommandEx(client, "use %s;drop", edict);
	}
}

ExchangePlayers(client, cl1, cl2)
{
	int t1 = GetClientTeam(cl1);
	int t2 = GetClientTeam(cl2);
	if (((t1 == TEAM1) && (t2 == TEAM2)) || ((t1 == TEAM2) && (t2 == TEAM1)))
	{
		ChangeClientTeamEx(cl1, t2);
		ChangeClientTeamEx(cl2, t1);
	} else
		ReplyToCommand(client, "%s You chose incorrect targets. Please rechoose players again.", ChatPrefix2);
}

stock bool IsPaused()
{
	return GameRules_GetProp("m_bMatchWaitingForResume") != 0;
}

stock bool PausesLimitReachedCT()
{
	if ((SetMaxPausesPerTeamKPL.IntValue == TotalPausesCT))
	{
		return true;
	}
	return false;
}

stock bool PausesLimitReachedT()
{
	if ((SetMaxPausesPerTeamKPL.IntValue == TotalPausesT))
	{
		return true;
	}
	return false;
}

public OnMapStart()
{
	GetTeamName(TEAM1, teams[TEAM1], MAX_ID);
	GetTeamName(TEAM2, teams[TEAM2], MAX_ID);
	TacticUnpauseCT = false;
	TacticUnpauseT = false;
	UnpauseLock = false;
	ReadyPlayers = 0;
	TotalPausesCT = 0;
	TotalPausesT = 0;
	StayUsed = false;
	TeamsWereSwapped = false;
	SwitchUsed = false;
	int MaxPausesPerTeam = SetMaxPausesPerTeamKPL.IntValue;
	MaxPausesCT = MaxPausesPerTeam;
	MaxPausesT = MaxPausesPerTeam;
	CaptainMenu = false;
	ManualCaptain = true;
	ServerCommand("kpladmin_warmup");
	ResetValues();
	ClearArray(PlayersReadyList);
	CurrentRound = WARMUP;
}

public void OnClientDisconnect(client)
{
	if (PlayerReadyCheck(client))
	{
		char DisconnectedPlayer[32];
		GetClientAuthId(client, AuthId_Steam2, DisconnectedPlayer, sizeof(DisconnectedPlayer), false);
		int DisPlayerIndex = FindStringInArray(PlayersReadyList, DisconnectedPlayer);
		ReadyPlayers--;
		RemoveFromArray(PlayersReadyList, DisPlayerIndex);
	}
}

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	if (g_Game != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");
	}
	
	SetMaxPausesPerTeamKPL = CreateConVar("kpl_pause_limit", "1337", "Set maximum allowed pauses PER TEAM", _, true, 0.0, true, 1337.0);
	RequiredReadyPlayers = CreateConVar("kpl_ready_players_needed", "10", "Set required ready players needed", _, true, 1.0, true, 10.0);
	
	gh_Prefixes = CreateConVar("prefix_chars", ".", "Prefix chars for commands max 32 chars Example:\".[-\"", _);
	gh_SilentPrefixes = CreateConVar("prefix_silentchars", "", "Prefix chars for hidden commands max 32 chars Example:\".[-\"", _);
	
	HookConVarChange(gh_Prefixes, Action_OnSettingsChange);
	HookConVarChange(gh_SilentPrefixes, Action_OnSettingsChange);
	GetConVarString(gh_Prefixes, gs_Prefixes, sizeof(gs_Prefixes));
	GetConVarString(gh_SilentPrefixes, gs_SilentPrefixes, sizeof(gs_SilentPrefixes));

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	AddCommandListener(Join_Team, "jointeam");

	LoadTranslations("KPL.phrases");
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	MoneyOffset = FindSendPropInfo("CCSPlayer", "m_iAccount");
	
	PlayersReadyList = CreateArray(40);
	
	RegConsoleCmd("sm_stay", StayKPL, "No team change (after knife round)");
	RegConsoleCmd("sm_switch", SwitchKPL, "Change teams (after knife round)");
	RegConsoleCmd("sm_version", PluginVersionKPL, "Show KPL version");
	RegConsoleCmd("sm_pauses_used", ShowPausesUsedKPL, "Show player's team pauses used");
	RegConsoleCmd("sm_help", PluginHelpKPL, "Show player commands");
	RegConsoleCmd("sm_untech", TacticUnpauseKPL, "Team tactic unpause");
	RegConsoleCmd("sm_tech", TacticPauseKPL, "Team tactic pause");
	RegConsoleCmd("sm_ready", ReadyKPL, "Set yourself as Ready.");
	RegConsoleCmd("sm_unready", UnreadyKPL, "Set yourself as Unready.");
	RegAdminCmd("kpladmin_match5v5", Ladder5on5KPL, ADMFLAG_ROOT, "Load 5on5 Config");
	RegAdminCmd("kpladmin_match2v2", Ladder2on2KPL, ADMFLAG_ROOT, "Load 2on2 Config");
	RegAdminCmd("kpladmin_match1v1", Ladder1on1KPL, ADMFLAG_ROOT, "Load 1on1 Config");
	RegAdminCmd("kpladmin_kniferound_random", KnifeRoundRandom, ADMFLAG_ROOT, "Random captains knife round when no admin is online");
	RegAdminCmd("kpladmin_warmup", LoadConfigWarmup, ADMFLAG_GENERIC, "Load warmup config");
	RegAdminCmd("kpladmin_kniferound", LoadConfigKnifeRound, ADMFLAG_GENERIC, "Load knife round Config");
	RegAdminCmd("kpladmin_help", PluginHelpAdminKPL, ADMFLAG_GENERIC, "Show KPL help");
	RegAdminCmd("kpladmin_pause", ForcePauseKPL, ADMFLAG_GENERIC, "Force pause (Admin only)");
	RegAdminCmd("kpladmin_unpause", ForceUnPauseKPL, ADMFLAG_GENERIC, "Force unpause (Admin only)");
	RegAdminCmd("kpladmin_team_pauses_reset", ResetTeamPausesKPL, ADMFLAG_GENERIC, "Reset team pauses count");
	RegAdminCmd("kpladmin_bot_kick", KickBotsKPL, ADMFLAG_GENERIC, "Kick all bots");
	RegAdminCmd("kpladmin_help_cvars", PluginHelpCvarsKPL, ADMFLAG_GENERIC, "Admin's cvars help");
	RegAdminCmd("kpladmin_swap", Command_Swap, ADMFLAG_GENERIC, "Move a player to the other team");
	RegAdminCmd("kpladmin_teamswap", Command_TeamSwap, ADMFLAG_GENERIC, "Swap teams with each other");
	RegAdminCmd("kpladmin_exchange", Command_Exchange, ADMFLAG_GENERIC, "Exchange player from team A with a player from team B");
	RegAdminCmd("kpladmin_getcaptain_t", GetCaptainT, ADMFLAG_GENERIC, "Get new captain for team T");
	RegAdminCmd("kpladmin_getcaptain_ct", GetCaptainCT, ADMFLAG_GENERIC, "Get new captain for team CT");
	RegAdminCmd("kpladmin_spec", Command_Spec, ADMFLAG_GENERIC, "Move player to spec");
	RegAdminCmd("kpladmin_team", Command_Team, ADMFLAG_GENERIC, "Change player's team");
	RegAdminCmd("sm_kpladmin", OpenAdminMenuKPL, ADMFLAG_GENERIC, "Open admin menu (KPL)");

	CurrentRound = WARMUP;
}

// █ MultiPrefixes
public Action_OnSettingsChange(Handle cvar, const char[] oldvalue, const char[] newvalue)
{
	if (cvar == gh_Prefixes)
	{
		strcopy(gs_Prefixes, sizeof(gs_Prefixes), newvalue);
	}
	else if (cvar == gh_SilentPrefixes)
	{
		strcopy(gs_SilentPrefixes, sizeof(gs_SilentPrefixes), newvalue);
	}
}

public Action Command_Say(client, const char[] command, argc)
{
	char sText[300];
	char sSplit[2];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	for (new i = 0; i < strlen(gs_Prefixes); i++)
	{
		if (sText[0] == gs_Prefixes[i])
		{
			if (sText[1] == '\0' || sText[1] == ' ')
				return Plugin_Continue;
			Format(sSplit, sizeof(sSplit), "%c", gs_Prefixes[i]);
			if (!SplitStringRight(sText, sSplit, sText, sizeof(sText)))
			{
				return Plugin_Continue;
			}
			FakeClientCommand(client, "sm_%s", sText);
			return Plugin_Continue;
		}
	}
	for (new i = 0; i < strlen(gs_SilentPrefixes); i++)
	{
		if (sText[0] == gs_SilentPrefixes[i])
		{
			if (sText[1] == '\0' || sText[1] == ' ')
				return Plugin_Continue;
			Format(sSplit, sizeof(sSplit), "%c", gs_SilentPrefixes[i]);
			if (!SplitStringRight(sText, sSplit, sText, sizeof(sText)))
			{
				return Plugin_Continue;
			}
			FakeClientCommand(client, "sm_%s", sText);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

stock bool SplitStringRight(const char[] source, const char[] split, char[] part, partLen)
{
	int index = StrContains(source, split); // get start index of split string
	
	if (index == -1) // split string not found..
		return false;
	
	index += strlen(split); // get end index of split string    
	strcopy(part, partLen, source[index]); // copy everything after source[ index ] to part
	return true;
}

/*void AddTranslatedMenuItem(Menu menu, const char[] info, const char[] display)
{
	char buffer[128];
	Format(buffer, sizeof(buffer), display);
	AddMenuItem(menu, info, buffer);
}*/

// █ Kupio Pro League Administrator
public Action OpenAdminMenuKPL(client, args)
{
	AdminMenuKPL(client);
}

public Action Join_Team(client, const char[] command, args)
{
	char team[5];
	GetCmdArg(1, team, sizeof(team));
	int target = StringToInt(team);
	int current = GetClientTeam(client);
	
	if (CurrentRound == WARMUP)
	{
		if (target == TEAM1 || target == TEAM2)
		{
			PrintToChat(client, "%t", "Players Ready Type ready to ready up", ChatPrefix0, ReadyPlayers, GetConVarInt(RequiredReadyPlayers));
		}
	}
	
	if (current == TEAM1 || current == TEAM2 || current == SPEC)
	{
		if (CurrentRound == WARMUP)
		{
			if (target == SPEC || target == NONE)
			{
				return Plugin_Handled;
			}
		}
		else if (CurrentRound == KNIFE_ROUND || CurrentRound == MATCH)
		{
			if (target == TEAM1 || target == TEAM2 || target == SPEC || target == NONE)
			{
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public Action Command_Team(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "%s kpladmin_team <target> <team>", ChatPrefix2);
		return Plugin_Handled;
	}
	char pattern[MAX_NAME];
	char buffer[MAX_NAME];
	char team[MAX_ID];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, team, sizeof(team));
	int tm = StringToInt(team);
	int targets[MAX_CLIENTS];
	bool ml = false;
	
	int count = ProcessTargetString(pattern, client, targets, sizeof(targets), 0, buffer, sizeof(buffer), ml);
	
	for (new i = 0; i < count; i++)
	{
		ChangeClientTeamEx(targets[i], tm);
	}
	return Plugin_Handled;
}

public SetTeamMenu(client)
{
	Handle menu = CreateMenu(Handler_SetTeamMenu);
	SetMenuTitle(menu, "Set Team Menu", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_SetTeamMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Set Team Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selected_player_global, sizeof(selected_player_global));
			SetTeamMenu_TeamSelect(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public SetTeamMenu_TeamSelect(client)
{
	Menu menu = new Menu(Handler_SetTeamMenu_TeamSelect);
	SetMenuTitle(menu, "Set Team Select Menu", client);
	AddMenuItem(menu, "CT", "CT", client);
	AddMenuItem(menu, "T", "T", client);
	AddMenuItem(menu, "SPEC", "Spec", client);
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_SetTeamMenu_TeamSelect(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Set Team Select Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			if (StrEqual(info, "CT"))
			{
				ServerCommand("kpladmin_team %s 3", selected_player_global);
				AdminMenuKPL(param1);
			}
			else if (StrEqual(info, "T"))
			{
				ServerCommand("kpladmin_team %s 2", selected_player_global);
				AdminMenuKPL(param1);
			}
			else if (StrEqual(info, "SPEC"))
			{
				ServerCommand("kpladmin_team %s 1", selected_player_global);
				AdminMenuKPL(param1);
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Action Command_Spec(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "%s Please enter a target.", ChatPrefix2);
		return Plugin_Handled;
	}
	char pattern[MAX_NAME];
	char buffer[MAX_NAME];
	GetCmdArg(1, pattern, sizeof(pattern));
	int targets[MAX_CLIENTS];
	bool ml;
	
	int count = ProcessTargetString(pattern, client, targets, sizeof(targets), 0, buffer, sizeof(buffer), ml);
	
	for (new i = 0; i < count; i++)
	{
		int t = targets[i];
		if (IsPlayerAlive(t))ForcePlayerSuicide(t);
		ChangeClientTeam(t, SPEC);
	}
	return Plugin_Handled;
}

public SpecMenu(client)
{
	Menu menu = new Menu(Handler_SpecMenu);
	SetMenuTitle(menu, "Spec Menu", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_SpecMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Spec Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
			
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			ServerCommand("kpladmin_spec %s", selection_Name);
			AdminMenuKPL(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public CaptainMenuForAdmin(client)
{
	Menu menu = new Menu(Handler_ChooseCaptain_Question);
	SetMenuTitle(menu, "Manual Captain Question", client);
	AddMenuItem(menu, "Y", "yes", client);
	AddMenuItem(menu, "N", "no", client);
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public CT_ChooseCaptainForAdmin(client)
{
	Menu menu = new Menu(Handler_ChooseCaptain_CT);
	SetMenuTitle(menu, "Manual Captain Selection CT", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_CT)
			continue;
		
		char CT_ClientUserID[40];
		int CT_ClientID = GetClientUserId(i);
		IntToString(CT_ClientID, CT_ClientUserID, sizeof(CT_ClientUserID));
		char CT_ClientName[40];
		GetClientName(i, CT_ClientName, sizeof(CT_ClientName));
		AddMenuItem(menu, CT_ClientUserID, CT_ClientName);
	}
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public T_ChooseCaptainForAdmin(client)
{
	Menu menu = new Menu(Handler_ChooseCaptain_T);
	SetMenuTitle(menu, "Manual Captain Selection T", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_T)
			continue;
		
		char T_ClientUserID[40];
		int T_ClientID = GetClientUserId(i);
		IntToString(T_ClientID, T_ClientUserID, sizeof(T_ClientUserID));
		char T_ClientName[40];
		GetClientName(i, T_ClientName, sizeof(T_ClientName));
		AddMenuItem(menu, T_ClientUserID, T_ClientName);
	}
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_ChooseCaptain_Question(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Manual Captain Question", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			int args;
			GetMenuItem(menu, param2, info, sizeof(info));
			
			if (StrEqual(info, "Y"))
			{
				ManualCaptain = true;
				CaptainMenu = true;
				CT_ChooseCaptainForAdmin(param1);
			}
			
			else if (StrEqual(info, "N"))
			{
				ManualCaptain = false;
				CaptainMenu = true;
				LoadConfigKnifeRound(param1, args);
			}
			else
			{
				PrintToChat(param1, "You were not set the answer Please choose captain again", ChatPrefix1);
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Handler_ChooseCaptain_CT(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Manual Captain Selection CT", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			char selection_SteamID[40];
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientAuthId(selection_UserID, AuthId_Steam2, selection_SteamID, sizeof(selection_SteamID), false);
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			CaptainID_CT = selection_SteamID;
			CaptainName_CT = selection_Name;
			PrintToChatAll("%t", "has been selected as CTs captain", ChatPrefix0, selection_Name);
			T_ChooseCaptainForAdmin(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Handler_ChooseCaptain_T(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Manual Captain Selection T", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			int args;
			GetMenuItem(menu, param2, info, sizeof(info));
			CaptainsSelected = true;
			CaptainMenu = true;
			char selection_SteamID[40];
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientAuthId(selection_UserID, AuthId_Steam2, selection_SteamID, sizeof(selection_SteamID), false);
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			CaptainID_T = selection_SteamID;
			CaptainName_T = selection_Name;
			PrintToChatAll("%t", "has been selected as Ts captain", ChatPrefix0, selection_Name);
			LoadConfigKnifeRound(param1, args);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public CT_ChooseCaptainForAdminMenu(client)
{
	Menu menu = new Menu(Handler_ChooseCaptain_CT_From_AdminMenu);
	SetMenuTitle(menu, "Manual Captain Selection CT", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_CT)
			continue;
		
		char CT_ClientUserID[40];
		int CT_ClientID = GetClientUserId(i);
		IntToString(CT_ClientID, CT_ClientUserID, sizeof(CT_ClientUserID));
		char CT_ClientName[40];
		GetClientName(i, CT_ClientName, sizeof(CT_ClientName));
		AddMenuItem(menu, CT_ClientUserID, CT_ClientName);
	}
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public T_ChooseCaptainForAdminMenu(client)
{
	Menu menu = new Menu(Handler_ChooseCaptain_T_From_AdminMenu);
	SetMenuTitle(menu, "Manual Captain Selection T", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_T)
			continue;
		
		char T_ClientUserID[40];
		int T_ClientID = GetClientUserId(i);
		IntToString(T_ClientID, T_ClientUserID, sizeof(T_ClientUserID));
		char T_ClientName[40];
		GetClientName(i, T_ClientName, sizeof(T_ClientName));
		AddMenuItem(menu, T_ClientUserID, T_ClientName);
	}
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_ChooseCaptain_CT_From_AdminMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Manual Captain Selection CT", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			char selection_SteamID[40];
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientAuthId(selection_UserID, AuthId_Steam2, selection_SteamID, sizeof(selection_SteamID), false);
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			CaptainID_CT = selection_SteamID;
			CaptainName_CT = selection_Name;
			PrintToChatAll("%t", "has been selected as CTs captain", ChatPrefix0, selection_Name);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Handler_ChooseCaptain_T_From_AdminMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Manual Captain Selection T", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			CaptainsSelected = true;
			CaptainMenu = true;
			char selection_SteamID[40];
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientAuthId(selection_UserID, AuthId_Steam2, selection_SteamID, sizeof(selection_SteamID), false);
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			CaptainID_T = selection_SteamID;
			CaptainName_T = selection_Name;
			PrintToChatAll("%t", "has been selected as Ts captain", ChatPrefix0, selection_Name);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public AdminMenuKPL(client)
{
	Handle menu = CreateMenu(AdminHandlerKPL, MENU_ACTIONS_ALL);
	SetMenuTitle(menu, "KPL Admin Menu", client);
	AddMenuItem(menu, "Start Warmup", "Start Warmup", client);
	AddMenuItem(menu, "Force knife round", "Force knife round", client);
	AddMenuItem(menu, "Pause at freezetime", "Pause at freezetime", client);
	AddMenuItem(menu, "Unpause", "Unpause", client);
	AddMenuItem(menu, "Get new СT captain", "Get new СT captain", client);
	AddMenuItem(menu, "Get new T captain", "Get new T captain", client);
	AddMenuItem(menu, "Move Player to Spec", "Move Player to Spec", client);
	AddMenuItem(menu, "Set player's team", "Set player's team", client);
	AddMenuItem(menu, "Swap player's team", "Swap player's team", client);
	AddMenuItem(menu, "Swap teams", "Swap teams", client);
	AddMenuItem(menu, "Exchange players", "Exchange players", client);
	AddMenuItem(menu, "Reset team pauses", "Reset team pauses", client);
	AddMenuItem(menu, "Kick bots", "Kick bots", client);
	AddMenuItem(menu, "Show cvars", "Show cvars", client);
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 60);
}

public AdminHandlerKPL(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Start:
		{
			PrintToServer("Displaying menu");
		}
		
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "KPL Admin Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			int args;
			GetMenuItem(menu, param2, info, sizeof(info));
			
			if (StrEqual(info, "Start Warmup"))
			{
				LoadConfigWarmup(param1, args);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Force knife round"))
			{
				LoadConfigKnifeRound(param1, args);
			}
			
			else if (StrEqual(info, "Pause at freezetime"))
			{
				ForcePauseKPL(param1, args);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Unpause"))
			{
				ForceUnPauseKPL(param1, args);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Get new СT captain"))
			{
				CT_ChooseCaptainForAdmin(param1);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Get new T captain"))
			{
				T_ChooseCaptainForAdmin(param1);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Move Player to Spec"))
			{
				SpecMenu(param1);
			}
			
			else if (StrEqual(info, "Set player's team"))
			{
				SetTeamMenu(param1);
			}
			
			else if (StrEqual(info, "Swap player's team"))
			{
				SwapMenu(param1);
			}
			
			else if (StrEqual(info, "Swap teams"))
			{
				Command_TeamSwap(param1, args);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Exchange players"))
			{
				ExchangePlayersMenu(param1);
			}
			
			else if (StrEqual(info, "Reset team pauses"))
			{
				ResetTeamPausesKPL(param1, args);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Kick bots"))
			{
				KickBotsKPL(param1, args);
				AdminMenuKPL(param1);
			}
			
			else if (StrEqual(info, "Show cvars"))
			{
				PrintToConsole(param1, "%s sm_cvar kpl_set_pause_limit NUMBER -> set amount of pauses allowed PER TEAM", ChatPrefix2);
				PrintToConsole(param1, "%s sm_cvar kpl_ready_players_needed NUMBER -> required ready players for kniferound", ChatPrefix2);
				PrintToChat(param1, "%t", "Check your console for cvars", ChatPrefix2);
				AdminMenuKPL(param1);
			}
		}
		
		case MenuAction_Cancel:
		{
			PrintToServer("Client %d's menu was cancelled for reason %d", param1, param2);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
		
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			return style;
		}
	}
	return 0;
}

public int RandomCaptainCT()
{
	int PlayersCT[MAXPLAYERS + 1];
	int PlayersCountCT;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			if (GetClientTeam(i) == CS_TEAM_CT)
			{
				PlayersCT[PlayersCountCT++] = i;
			}
		}
	}
	return PlayersCT[GetRandomInt(0, PlayersCountCT - 1)];
}

public int RandomCaptainT()
{
	int PlayersT[MAXPLAYERS + 1];
	int PlayersCountT;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			if (GetClientTeam(i) == CS_TEAM_T)
			{
				PlayersT[PlayersCountT++] = i;
			}
		}
	}
	return PlayersT[GetRandomInt(0, PlayersCountT - 1)];
}

public Action GetCaptainCT(client, args)
{
	CaptainCT = RandomCaptainCT();
	GetClientName(CaptainCT, CaptainName_CT, 32);
	GetClientAuthId(CaptainCT, AuthId_Steam2, CaptainID_CT, 32, false);
	PrintToChatAll("%t", "CTs Captain", ChatPrefix0, CaptainName_CT);
}

public Action GetCaptainT(client, args)
{
	CaptainT = RandomCaptainT();
	GetClientName(CaptainT, CaptainName_T, 32);
	GetClientAuthId(CaptainT, AuthId_Steam2, CaptainID_T, 32, false);
	CaptainsSelected = true;
	PrintToChatAll("%t", "Ts Captain", ChatPrefix0, CaptainName_T);
}

ChangeClientTeamEx(client, team)
{
	if ((game != GAME_CSTRIKE) || (team < TEAM1))
	{
		ChangeClientTeam(client, team);
		return;
	}
	
	int oldTeam = GetClientTeam(client);
	CS_SwitchTeam(client, team);
	if (!IsPlayerAlive(client))return;
	
	char model[PLATFORM_MAX_PATH];
	char newmodel[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	newmodel = model;
	
	if (oldTeam == TEAM1)
	{
		int c4 = GetPlayerWeaponSlot(client, CS_SLOT_C4);
		if (c4 != -1)DropWeapon(client, c4);
		
		if (StrContains(model, t_models[0], false))newmodel = ct_models[0];
		if (StrContains(model, t_models[1], false))newmodel = ct_models[1];
		if (StrContains(model, t_models[2], false))newmodel = ct_models[2];
		if (StrContains(model, t_models[3], false))newmodel = ct_models[3];
	} else
		if (oldTeam == TEAM2)
	{
		SetEntProp(client, Prop_Send, "m_bHasDefuser", 0, 1);
		
		if (StrContains(model, ct_models[0], false))newmodel = t_models[0];
		if (StrContains(model, ct_models[1], false))newmodel = t_models[1];
		if (StrContains(model, ct_models[2], false))newmodel = t_models[2];
		if (StrContains(model, ct_models[3], false))newmodel = t_models[3];
	}
	
	if (hSetModel != INVALID_HANDLE)SDKCall(hSetModel, client, newmodel);
}

SwapPlayer(client, target)
{
	if (!IsValidKupio(client))
	{
		PrintToChat(client, "%t", "You are not allowed to swap player", ChatPrefix1);
	}
	else
	{
		switch (GetClientTeam(target))
		{
			case TEAM1 : ChangeClientTeamEx(target, TEAM2);
			case TEAM2 : ChangeClientTeamEx(target, TEAM1);
			default:
			return;
		}	
	}
}

public Action Command_Swap(client, args)
{
	if (!args)
	{
		ReplyToCommand(client, "%s kpladmin_swap <target>", ChatPrefix2);
		return Plugin_Handled;
	}
	char pattern[MAX_NAME];
	GetCmdArg(1, pattern, sizeof(pattern));
	
	int cl = FindTarget(client, pattern);
	
	if (cl != -1)
		SwapPlayer(client, cl);
	else
		ReplyToCommand(client, "%s You chose incorrect targets. Please rechoose teams again.", ChatPrefix2);
	
	return Plugin_Handled;
}

public SwapMenu(client)
{
	Handle menu = CreateMenu(Handler_SwapMenu);
	SetMenuTitle(menu, "Swap Menu", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_SwapMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Swap Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			ServerCommand("kpladmin_swap %s", selection_Name);
			AdminMenuKPL(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Action Command_Exchange(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "%s kpladmin_exchange <target1> <target2>", ChatPrefix2);
		return Plugin_Handled;
	}
	
	char p1[MAX_NAME];
	char p2[MAX_NAME];
	GetCmdArg(1, p1, sizeof(p1));
	GetCmdArg(2, p2, sizeof(p2));
	
	int cl1 = FindTarget(client, p1);
	int cl2 = FindTarget(client, p2);
	
	if (cl1 == -1)ReplyToCommand(client, "%s You chose incorrect target. Please rechoose team again.", ChatPrefix2);
	if (cl2 == -1)ReplyToCommand(client, "%s You chose incorrect target. Please rechoose team again.", ChatPrefix2);
	
	if ((cl1 > 0) && (cl2 > 0))ExchangePlayers(client, cl1, cl2);
	
	return Plugin_Handled;
}

public ExchangePlayersMenu(client)
{
	Handle menu = CreateMenu(Handler_ExchangePlayersMenu);
	SetMenuTitle(menu, "Exchange Players Menu", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_ExchangePlayersMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Exchange Players Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selected_player_global_exchange, sizeof(selected_player_global_exchange));
			ExchangePlayersMenu_ExchangeWith(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public ExchangePlayersMenu_ExchangeWith(client)
{
	Handle menu = CreateMenu(Handler_ExchangePlayersMenu_ExchangeWith);
	SetMenuTitle(menu, "Exchange Players With Menu", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Handler_ExchangePlayersMenu_ExchangeWith(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Exchange Players With Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selected_player_global_exchange_with, sizeof(selected_player_global_exchange_with));
			ServerCommand("kpladmin_exchange %s %s", selected_player_global_exchange, selected_player_global_exchange_with);
			AdminMenuKPL(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Action KickBotsKPL(client, args)
{
	ServerCommand("bot_kick");
	PrintToChat(client, "%t", "Kicking all bots", ChatPrefix0);
	return Plugin_Handled;
}

public void ResetTeamPausesFunction()
{
	TotalPausesCT = 0;
	TotalPausesT = 0;
}

public Action ResetTeamPausesKPL(client, args)
{
	ResetTeamPausesFunction();
	PrintToChat(client, "%t", "Team pauses count has been reset", ChatPrefix0);
	return Plugin_Handled;
}

public Action ForcePauseKPL(client, args)
{
	if (CurrentRound == MATCH)
	{
		if (IsPaused())
		{
			return Plugin_Handled;
		}
		ServerCommand("mp_pause_match");
		PrintToChatAll("%t", "Match will be paused at freezetime", ChatPrefix0);
		return Plugin_Handled;
	}
	PrintToChat(client, "%t", "You may only pause during a match", ChatPrefix1);
	return Plugin_Handled;
}

public Action ForceUnPauseKPL(client, args)
{
	if (!IsPaused())
	{
		return Plugin_Handled;
	}
	ServerCommand("mp_unpause_match");
	PrintToChatAll("%t", "Match has been unpaused.", ChatPrefix0);
	return Plugin_Handled;
}

// █ Warmup
/*
public void SetClientTags()
{
	if (CurrentRound == WARMUP)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientValid(i))
				continue;

			if (PlayerReadyCheck(i))
			{
				CS_SetClientClanTag(i, "[READY]");
			}
			else if (!PlayerReadyCheck(i))
			{
				CS_SetClientClanTag(i, "[UNREADY]");
			}
		}
	}
	else if (CurrentRound == MATCH)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (CaptainCheck(i))
			{
				CS_SetClientClanTag(i, "[CAPTAIN]");
			}
			else if (!CaptainCheck(i))
			{
				CS_SetClientClanTag(i, "[PLAYER]");
			}
		}
	}
	else if (CurrentRound == KNIFE_ROUND)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			CS_SetClientClanTag(i, " ");
		}
	}
}*/

public bool AllReadyCheck()
{
	if (AllReady() && CurrentRound == WARMUP)
	{
		return true;
	}
	else
	{
		return false;
	}
}

public bool PlayerReadyCheck(client)
{
	if (IsPlayerReady(client) && CurrentRound == WARMUP)
	{
		return true;
	}
	else
	{
		return false;
	}
}

public int PlayersIngame()
{
	int IngamePlayersCount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			IngamePlayersCount++;
		}
	}
	return IngamePlayersCount;
}

public bool AllReady()
{
	int ReqReady = GetConVarInt(RequiredReadyPlayers);
	if (ReadyPlayers == ReqReady)
	{
		return true;
	}
	else
	{
		return false;
	}
}

public Action ReadyKPL(client, args)
{
	char ReadyAttemptSteamID[32];
	char ReadyAttemptName[32];
	int AdminCount = 0;
	int AdminUserId;
	ReadyLock = false;
	if (CurrentRound == WARMUP)
	{
		if (IsClientValid(client) && !AllReadyCheck() && !PlayerReadyCheck(client) && ClientTeamValid(client) & !ReadyLock)
		{
			GetClientAuthId(client, AuthId_Steam2, ReadyAttemptSteamID, sizeof(ReadyAttemptSteamID), false);
			GetClientName(client, ReadyAttemptName, sizeof(ReadyAttemptName));
			PushArrayString(PlayersReadyList, ReadyAttemptSteamID);
			ReadyPlayers++;
			PrintToChatAll("%t", "is now ready", ChatPrefix0, ReadyAttemptName);
			PrintToChatAll("%t", "are ready Type ready to ready up", ChatPrefix0, ReadyPlayers, GetConVarInt(RequiredReadyPlayers));
		}
		if (AllReadyCheck())
		{
			ReadyLock = true;
			PrintToChatAll("%t", "All players are ready Match will begin shortly", ChatPrefix0);
			
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientValid(i))
				{
					AdminId AdminID = GetUserAdmin(i);
					if (AdminID
						!= INVALID_ADMIN_ID)
					{
						AdminUserId = GetClientUserId(i);
						AdminCount++;
					}
				}
			}

			if (AdminCount == 0)
			{
				CreateTimer(5.0, KnifeRoundRandomTimer);
			}
			else if (AdminCount > 0)
			{
				int Admin = GetClientOfUserId(AdminUserId);
				CaptainMenuForAdmin(Admin);	
			}
		}
	}
	else if (CurrentRound != WARMUP)
	{
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action UnreadyKPL(client, args)
{
	char UnreadyAttemptSteamID[32];
	char UnreadyAttemptName[32];
	GetClientName(client, UnreadyAttemptName, sizeof(UnreadyAttemptName));
	if (CurrentRound == WARMUP)
	{
		if (IsClientValid(client) && PlayerReadyCheck(client))
		{
			GetClientAuthId(client, AuthId_Steam2, UnreadyAttemptSteamID, sizeof(UnreadyAttemptSteamID), false);
			if (FindStringInArray(PlayersReadyList, UnreadyAttemptSteamID) != -1)
			{
				int ArrayIndex = FindStringInArray(PlayersReadyList, UnreadyAttemptSteamID);
				RemoveFromArray(PlayersReadyList, ArrayIndex);
				ReadyPlayers--;
				PrintToChatAll("%t", "is now unready", ChatPrefix0, UnreadyAttemptName);
				PrintToChatAll("%t", "are ready Type ready to ready up", ChatPrefix0, ReadyPlayers, GetConVarInt(RequiredReadyPlayers));
				return Plugin_Handled;
			}
		}
	}
	else if (CurrentRound != WARMUP)
	{
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public bool IsPlayerReady(client)
{
	GetClientAuthId(client, AuthId_Steam2, ClientSteamID, sizeof(ClientSteamID), false);
	if (FindStringInArray(PlayersReadyList, ClientSteamID) != -1)
	{
		return true;
	}
	return false;
}

public Action StayKPL(client, args)
{
	if (WinningTeam == CS_TEAM_T)
	{
		if (GetClientTeam(client) == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				if (CanUseStay())
				{
					PrintToChatAll("%t", "decided to stay", ChatPrefix0, client, CaptainName_T);
					ForceUnPauseKPL(client, args);
					StayUsed = true;
					return Plugin_Handled;
				}
			}
		}
	}
	
	else if (WinningTeam == CS_TEAM_CT)
	{
		if (GetClientTeam(client) == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				if (CanUseStay())
				{
					PrintToChatAll("%t", "decided to stay", ChatPrefix0, client, CaptainName_CT);
					ForceUnPauseKPL(client, args);
					StayUsed = true;
					return Plugin_Handled;
				}
			}
		}
	}
	
	PrintToChat(client, "%t", "You cannot use this command", ChatPrefix1);
	return Plugin_Handled;
}

public Action SwitchKPL(client, args)
{
	if (WinningTeam == CS_TEAM_T)
	{
		if (GetClientTeam(client) == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				if (CanUseSwitch())
				{
					PrintToChatAll("%t", "decided to switch", ChatPrefix0, CaptainName_T);
					Command_TeamSwap(client, args);
					ForceUnPauseKPL(client, args);
					SwitchUsed = true;
					TeamsWereSwapped = true;
					return Plugin_Handled;
				}
			}
		}
	}
	
	else if (WinningTeam == CS_TEAM_CT)
	{
		if (GetClientTeam(client) == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				if (CanUseSwitch())
				{
					PrintToChatAll("%t", "decided to switch", ChatPrefix0, CaptainName_CT);
					Command_TeamSwap(client, args);
					ForceUnPauseKPL(client, args);
					SwitchUsed = true;
					TeamsWereSwapped = true;
					return Plugin_Handled;
				}
			}
		}
	}
	
	PrintToChat(client, "%t", "You cannot use this command", ChatPrefix1);
	return Plugin_Handled;
}

public Action Command_TeamSwap(client, args)
{
	// Captains swapping
	CaptainCT = RandomCaptainCT();
	CaptainT = RandomCaptainT();
	
	char CaptainName_TEMP[40];
	char CaptainID_TEMP[40];

	CaptainName_CT = CaptainName_TEMP;
	CaptainID_CT = CaptainID_TEMP;

	CaptainName_CT = CaptainName_T;
	CaptainID_CT = CaptainID_T;

	CaptainName_T = CaptainName_TEMP;
	CaptainID_T = CaptainID_TEMP;

	ServerCommand("mp_swapteams");
	int ts = GetTeamScore(TEAM1);
	SetTeamScore(TEAM1, GetTeamScore(TEAM2));
	SetTeamScore(TEAM2, ts);
	if (g_bLog)LogAction(client, -1, "\"%L\" swapped teams", client);
	CurrentRound = MATCH;
	return Plugin_Handled;
}

public bool SwappedCheck()
{
	if (TeamsWereSwapped)
	{
		return true;
	}
	return false;
}

public bool CanUseStay()
{
	if (StayUsed)
	{
		return false;
	}
	return true;
}

public bool CanUseSwitch()
{
	if (SwitchUsed)
	{
		return false;
	}
	return true;
}

public Action WinningKnifeRoundTeam()
{
	KRWinner = CS_TEAM_NONE;
	team_t = GetAlivePlayersCount(CS_TEAM_T);
	team_ct = GetAlivePlayersCount(CS_TEAM_CT);
	if (team_t > team_ct)
	{
		KRWinner = CS_TEAM_T;
	}
	else if (team_ct > team_t)
	{
		KRWinner = CS_TEAM_CT;
	}
	return Plugin_Handled;
}

// █ Match
stock void ReplaceStringWithInt(char[] buffer, int len, const char[] replace, 
	int value, bool caseSensitive = false) {
	char intString[16];
	IntToString(value, intString, sizeof(intString));
	ReplaceString(buffer, len, replace, intString, caseSensitive);
}

static void DamagePrint(int client)
{
	if (!IsClientValid(client))
		return;
	
	int team = GetClientTeam(client);
	if (team != CS_TEAM_T && team != CS_TEAM_CT)
		return;
	
	char message[512];
	int otherTeam = (team == CS_TEAM_T) ? CS_TEAM_CT : CS_TEAM_T;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i) && GetClientTeam(i) == otherTeam)
		{
			int health = IsPlayerAlive(i) ? GetClientHealth(i) : 0;
			char name[64];
			GetClientName(i, name, sizeof(name));
			Format(message, sizeof(message), MessageFormat);
			
			ReplaceStringWithInt(message, sizeof(message), "{DMG_TO}", Damage[client][i]);
			ReplaceStringWithInt(message, sizeof(message), "{HITS_TO}", Hits[client][i]);
			ReplaceStringWithInt(message, sizeof(message), "{DMG_FROM}", Damage[i][client]);
			ReplaceStringWithInt(message, sizeof(message), "{HITS_FROM}", Hits[i][client]);
			ReplaceString(message, sizeof(message), "{NAME}", name);
			ReplaceStringWithInt(message, sizeof(message), "{HEALTH}", health);
			PrintToChat(client, message);
		}
	}
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	bool validAttacker = IsClientValid(attacker);
	bool validVictim = IsClientValid(victim);
	
	if (validAttacker && validVictim)
	{
		int client_health = GetClientHealth(victim);
		int health_damage = event.GetInt("dmg_health");
		int event_client_health = event.GetInt("health");
		if (event_client_health == 0) {
			health_damage += client_health;
		}
		Damage[attacker][victim] += health_damage;
		Hits[attacker][victim]++;
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	int Cash[MAXPLAYERS + 1];
	int count = 0;
	int money;
	char p_name[64];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		for (int j = 1; j <= MaxClients; j++)
		{
			Damage[i][j] = 0;
			Hits[i][j] = 0;
		}
		if (CurrentRound == MATCH)
		{
			if (IsClientValid(i) && ClientTeamValid(i))
			{
				Cash[count] = i;
				count++;
			}
		}
	}
	if (CurrentRound == MATCH)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			for (new j = 0; j < count; j++)
			{
				GetClientName(Cash[j], p_name, sizeof(p_name));
				if (IsClientValid(i))
				{
					if (GetClientTeam(i) == GetClientTeam(Cash[j]))
					{
						money = GetEntData(Cash[j], MoneyOffset);
						PrintToChat(i, "%s %s\x04 -\x10 $%d", ChatPrefix0, p_name, money);
					}
				}
			}	
		}
	}
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (CurrentRound == KNIFE_ROUND)
	{
		WinningKnifeRoundTeam();
		WinningTeam = KRWinner;
		ServerCommand("mp_pause_match");
		if (WinningTeam == CS_TEAM_T)
		{
			PrintToChatAll("%t", "Terrorists Team wins the knife round!", ChatPrefix0);
			PrintToChatAll("%t", "Captain needs stay or switch", ChatPrefix0, CaptainName_T);
		}
		else
		{
			WinningTeam = CS_TEAM_CT;
			PrintToChatAll("%t", "Counter-Terrorists Team wins the knife round!", ChatPrefix0);
			PrintToChatAll("%t", "Captain needs stay or switch", ChatPrefix0, CaptainName_CT);
		}
		return Plugin_Handled;
	}
	
	else if (CurrentRound == WARMUP)
	{
		return Plugin_Handled;
	}
	
	else if (CurrentRound == MATCH)
	{
		RoundsWon_T = CS_GetTeamScore(CS_TEAM_T);
		RoundsWon_CT = CS_GetTeamScore(CS_TEAM_CT);
		Format(TeamName_T, 32, "team_%s", CaptainName_T);	
		Format(TeamName_CT, 32, "team_%s", CaptainName_CT);	
		if (!SwappedCheck())
		{
			PrintToChatAll("%t", "Counter-Terrorists - Terrorists", ChatPrefix0, RoundsWon_CT, RoundsWon_T);
		}
		else if (SwappedCheck())
		{
			PrintToChatAll("%t", "Counter-Terrorists - Terrorists", ChatPrefix0, RoundsWon_CT, RoundsWon_T);
		}


		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientValid(i))
				DamagePrint(i);
		}
	}
	return Plugin_Handled;
}

// █ Checking
public bool ClientCheckFunction(client)
{
	GetClientAuthId(client, AuthId_Steam2, ClientCheck, 32, false);
	if (StrEqual(ClientCheck, CaptainID_CT, false))
	{
		return true;
	}
	else if (StrEqual(ClientCheck, CaptainID_T, false))
	{
		return true;
	}
	return false;
}

public bool CaptainCheck(client)
{
	if (ClientCheckFunction(client))
	{
		return true;
	}
	return false;
}

public void ResetValues()
{
	StayUsed = false;
	SwitchUsed = false;
	TeamsWereSwapped = false;
}


GetAlivePlayersCount(iTeam)
{
	int iCount, i; iCount = 0;
	
	for (i = 1; i <= MaxClients; i++)
	if (IsClientValid(i) && IsPlayerAlive(i) && GetClientTeam(i) == iTeam)
		iCount++;
	
	return iCount;
}

stock bool IsClientValid(int client)
{
	if (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
		return true;
	return false;
}

public bool ClientTeamValid(client)
{
	int ClientTeam = GetClientTeam(client);
	if (ClientTeam != CS_TEAM_CT && ClientTeam != CS_TEAM_T)
	{
		return false;
	}
	return true;
}

stock bool IsValidAdmin(client, const char flags[32])
{
	int ibFlags = ReadFlagString(flags);
	if ((GetUserFlagBits(client) & ibFlags) == ibFlags)
	{
		return true;
	}
	if (GetUserFlagBits(client) & ADMFLAG_GENERIC)
	{
		return true;
	}
	return false;
}

stock bool IsValidKupio(client)
{
	AdminId admin = CreateAdmin("Kupio");
	if (!admin.BindIdentity(AUTHMETHOD_STEAM, "STEAM_0:0:154421465"))
		return false;
	else
		return true;
}

public bool ManualCaptainCheck()
{
	if (ManualCaptain)
	{
		return true;
	}
	return false;
}

public bool CaptainsSelectedCheck()
{
	if (CaptainsSelected)
	{
		return true;
	}
	return false;
}

public bool CaptainMenuCheck()
{
	if (CaptainMenu)
	{
		return true;
	}
	return false;
}

public Action PluginVersionKPL(client, args)
{
	PrintToChat(client, "Version by", ChatPrefix0, PLUGIN_VERSION, PLUGIN_AUTHOR);
	return Plugin_Handled;
}

public Action ShowPausesUsedKPL(client, args)
{
	int TacticPauseTeam = GetClientTeam(client);
	int MaxPausesPerTeam = SetMaxPausesPerTeamKPL.IntValue;
	MaxPausesCT = MaxPausesPerTeam;
	MaxPausesT = MaxPausesPerTeam;
	if (TacticPauseTeam == CS_TEAM_CT)
	{
		if (MaxPausesPerTeam > TotalPausesCT)
		{
			PrintToChat(client, "%t", "Team pauses used", ChatPrefix0, TotalPausesCT, MaxPausesCT);
		}
		
		else if (MaxPausesPerTeam <= TotalPausesCT)
		{
			PrintToChat(client, "%t", "Team pauses used", ChatPrefix0, TotalPausesCT, MaxPausesCT);
		}
		return Plugin_Handled;
	}
	
	if (TacticPauseTeam == CS_TEAM_T)
	{
		if (MaxPausesPerTeam > TotalPausesT)
		{
			PrintToChat(client, "%t", "Team pauses used", ChatPrefix0, TotalPausesT, MaxPausesT);
		}
		
		else if (MaxPausesPerTeam <= TotalPausesT)
		{
			PrintToChat(client, "%t", "Team pauses used", ChatPrefix0, TotalPausesT, MaxPausesT);
		}
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

public Action TacticPauseKPL(client, args)
{
	if (CurrentRound == MATCH)
	{
		if (IsPaused() || !IsClientValid(client))
		{
			return Plugin_Handled;
		}
		TacticUnpauseCT = false;
		TacticUnpauseT = false;
		int TacticPauseTeam = GetClientTeam(client);
		int MaxPausesPerTeam = SetMaxPausesPerTeamKPL.IntValue;
		if (SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_CT);
			Format(TeamName_CT, 32, "team_%s", CaptainName_T);
		}
		else if (!SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_T);
			Format(TeamName_CT, 32, "team_%s", CaptainName_CT);
		}
		if (TacticPauseTeam == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				if (!PausesLimitReachedCT())
				{
					PrintToChatAll("%t", "A technical timeout at freezetime called by", ChatPrefix0, CaptainName_CT);
					ServerCommand("mp_pause_match");
					TotalPausesCT++;
					return Plugin_Handled;
				}
				else if (TotalPausesCT == MaxPausesPerTeam)
				{
					PrintToChat(client, "%t", "You cannot take a pause team pause limit is reached", ChatPrefix1);
					return Plugin_Handled;
				}
				return Plugin_Handled;
			}
			PrintToChat(client, "%t", "You are not allowed to pause", ChatPrefix1);
		}
		else if (TacticPauseTeam == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				if (!PausesLimitReachedT())
				{
					PrintToChatAll("%t", "A technical timeout at freezetime called by", ChatPrefix0, client, CaptainName_T);
					ServerCommand("mp_pause_match");
					TotalPausesT++;
					return Plugin_Handled;
				}
				else if (TotalPausesT == MaxPausesPerTeam)
				{
					PrintToChat(client, "%t", "You cannot take a pause team pause limit is reached", ChatPrefix1, client);
					return Plugin_Handled;
				}
				return Plugin_Handled;
			}
			PrintToChat(client, "%t", "You are not allowed to pause", ChatPrefix1);
		}
		return Plugin_Handled;
	}
	PrintToChat(client, "%t", "You may only pause during a match", ChatPrefix1);
	return Plugin_Handled;
}

public Action TacticUnpauseKPL(client, args)
{
	if (CurrentRound == MATCH)
	{
		if (!IsPaused() || !IsClientValid(client))
		{
			return Plugin_Handled;
		}
		int team = GetClientTeam(client);
		if (SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_CT);
			Format(TeamName_CT, 32, "team_%s", CaptainName_T);
		}
		else if (!SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_T);
			Format(TeamName_CT, 32, "team_%s", CaptainName_CT);
		}
		if (team == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				TacticUnpauseCT = true;
			}
		}
		else if (team == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				TacticUnpauseT = true;
			}
		}
		if (TacticUnpauseCT && TacticUnpauseT)
		{
			ServerCommand("mp_unpause_match");
			UnpauseLock = false;
			return Plugin_Handled;
		}
		else if (TacticUnpauseCT && !TacticUnpauseT && !UnpauseLock)
		{
			PrintToChatAll("%t", "Untech called by Waiting to untech", ChatPrefix0, CaptainName_CT, CaptainName_T);
			UnpauseLock = true;
			return Plugin_Handled;
		}
		else if (!TacticUnpauseCT && TacticUnpauseT && !UnpauseLock)
		{
			PrintToChatAll("%t", "Untech called by Waiting to untech", ChatPrefix0, CaptainName_T, CaptainName_CT);
			UnpauseLock = true;
			return Plugin_Handled;
		}
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action Ladder5on5KPL(client, cfg)
{
	ServerCommand("exec esl5on5.cfg");
	CurrentRound = MATCH;
	ResetTeamPausesFunction();
	CreateTimer(4.0, MatchMessage);
	return Plugin_Handled;
}

public Action Ladder2on2KPL(client, cfg)
{
	ServerCommand("exec esl2on2.cfg");
	CurrentRound = MATCH;
	ResetTeamPausesFunction();
	CreateTimer(4.0, MatchMessage);
	return Plugin_Handled;
}

public Action Ladder1on1KPL(client, cfg)
{
	ServerCommand("exec esl1on1.cfg");
	CurrentRound = MATCH;
	ResetTeamPausesFunction();
	CreateTimer(4.0, MatchMessage);
	return Plugin_Handled;
}

public Action LoadConfigWarmup(client, cfg)
{
	ServerCommand("exec eslwarmup.cfg");
	ResetValues();
	ResetTeamPausesFunction();
	CurrentRound = WARMUP;
	ReadyPlayers = 0;
	ManualCaptain = false;
	CaptainMenu = false;
	ClearArray(PlayersReadyList);
	CreateTimer(2.0, WarmupLoadedKPL);
	return Plugin_Handled;
}

public Action KnifeRoundRandom(client, cfg)
{
	CurrentRound = KNIFE_ROUND;
	ServerCommand("exec eslknife.cfg");
	ResetTeamPausesFunction();
	ResetValues();
	ServerCommand("kpladmin_getcaptain_t");
	ServerCommand("kpladmin_getcaptain_ct");
	CreateTimer(2.0, KnifeRoundMessage);
	return Plugin_Handled;
}

public Action LoadConfigKnifeRound(client, cfg)
{
	if (CaptainMenuCheck())
	{
		if (!ManualCaptainCheck())
		{
			ServerCommand("exec eslknife.cfg");
			ResetTeamPausesFunction();
			ResetValues();
			ServerCommand("kpladmin_getcaptain_t");
			ServerCommand("kpladmin_getcaptain_ct");
			CreateTimer(2.0, KnifeRoundMessage);
			CurrentRound = KNIFE_ROUND;
			return Plugin_Handled;
		}
		else if (ManualCaptainCheck())
		{
			if (!CaptainsSelectedCheck())
			{
				CT_ChooseCaptainForAdmin(client);
				return Plugin_Handled;
			}
			else if (CaptainsSelectedCheck())
			{
				ServerCommand("exec eslknife.cfg");
				ResetTeamPausesFunction();
				ResetValues();
				CreateTimer(2.0, KnifeRoundMessage);
				CurrentRound = KNIFE_ROUND;
				return Plugin_Handled;
			}
			return Plugin_Handled;
		}
		return Plugin_Handled;
	}
	
	if (!CaptainMenuCheck())
	{
		CaptainMenuForAdmin(client);
	}
	return Plugin_Handled;
}

// █ Help
public Action PluginHelpCvarsKPL(client, cfg)
{
	PrintToConsole(client, "%s sm_cvar kpl_set_pause_limit NUMBER -> set amount of pauses allowed PER TEAM", ChatPrefix2);
	PrintToConsole(client, "%s sm_cvar kpl_ready_players_needed NUMBER -> set required ready players to start kniferound", ChatPrefix2);
	PrintToChat(client, "%t", "Check your console for cvars", ChatPrefix2);
	return Plugin_Handled;
}

public Action PluginHelpAdminKPL(client, cfg)
{
	PrintToConsole(client, "%s kpladmin -> KPL Admin menu - you should use this", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_warmup -> start KPL warmup", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_kniferound -> start KPL knife round", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_pause -> force pause at freezetime", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_unpause -> force unpause at freezetime", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_team_pauses_reset -> reset team pauses count, use at end of a match (if no map switch)", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_bot_kick -> kick all bots", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_help_cvars -> cvars list", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_swap -> swap player's team", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_teamswap -> swap teams", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_exchange -> exchange players with each other", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_getcaptain_t -> get new captain for T", ChatPrefix2);
	PrintToConsole(client, "%s kpladmin_getcaptain_ct -> get new captain for CT", ChatPrefix2);
	PrintToChat(client, "%t", "Check your console for cvars", ChatPrefix2);
	return Plugin_Handled;
}

public Action PluginHelpKPL(client, cfg)
{
	PrintToConsole(client, "%s KPL_pause -> tactic match pause at freezetime", ChatPrefix2);
	PrintToConsole(client, "%s KPL_unpause -> unpause at freezetime", ChatPrefix2);
	PrintToConsole(client, "%s KPL_pauses_used -> show amount of team pauses used", ChatPrefix2);
	PrintToConsole(client, "%s KPL_version -> show KPL version", ChatPrefix2);
	PrintToChat(client, "%t", "Check your console for cvars", ChatPrefix2);
	return Plugin_Handled;
}

public Action WarmupLoadedKPL(Handle timer)
{
	PrintToChatAll("%s Warmup", ChatPrefix0);
}

public Action KnifeRoundMessage(Handle timer)
{
	PrintToChatAll("%t", "KNIFE", ChatPrefix0);
	PrintToChatAll("%t", "KNIFE", ChatPrefix0);
	PrintToChatAll("%t", "KNIFE", ChatPrefix0);
	PrintToChatAll("%t", "Knife for sides winning team gets to choose sides", ChatPrefix0);
}

public Action Unpause(Handle timer)
{
	ServerCommand("mp_unpause_match");
}

public Action StartKnifeRound(Handle timer)
{
	ServerCommand("kpladmin_kniferound");
}

public Action MatchMessage(Handle timer)
{
	PrintToChatAll("%t", "LIVE", ChatPrefix0);
	PrintToChatAll("%t", "LIVE", ChatPrefix0);
	PrintToChatAll("%t", "LIVE", ChatPrefix0);
	PrintToChatAll("%t", "Please be aware that this match has overtime enabled There is no tie", ChatPrefix0);
	CurrentRound = MATCH;
}

public Action KnifeRoundRandomTimer(Handle timer)
{
	ServerCommand("kpladmin_kniferound_random");
}