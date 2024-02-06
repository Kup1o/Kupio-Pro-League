#include <sourcemod>
#include <multicolors>

int prevRound = 0;
int restRound = 0;
bool restored = false;
Handle hRestartGame = INVALID_HANDLE;
char ChatPrefix0[50] = " \x04[Kupio Pro League]";
char ChatPrefix1[50] = " \x07[Kupio Pro League]";
char ChatPrefix2[50] = " [Kupio Pro League]";


public Plugin myinfo =
{
	name = "[Kupio Pro League] Round Restore",
	author = "MoeJoe111 & Kupio",
	description = "Restore round backups with sourcemod",
	version = "942",
	url = "https://github.com/MoeJoe111/RoundRestore"
};

public void OnPluginStart()
{		
	/* Hooks */
	HookEvent("cs_match_end_restart", Event_CsMatchEndRestart);
	HookEvent("round_start", Event_RoundStart);
	/* Plugin Commands */
	RegAdminCmd("sm_restore", MainMenu, ADMFLAG_ROOT, "[RR] Displays the Round Restore menu");
	RegAdminCmd("sm_restorelast", VoteLast, ADMFLAG_ROOT, "[RR] Displays the Round Restore menu");
	/* mp_restartgame Hook */
	hRestartGame = FindConVar("mp_restartgame");
	if(hRestartGame != INVALID_HANDLE)
	{
		HookConVarChange(hRestartGame, GameRestartChanged);
	}		
	ServerCommand("mp_backup_restore_load_autopause 0");
	ServerCommand("mp_backup_round_auto 1");
	/* Translation */
	LoadTranslations("RoundRestore.phrases");
}

public void Event_CsMatchEndRestart(Event event, const char[] name, bool dontBroadcast)
{
	prevRound = 0;

	char buffer[255];
	Format(buffer, sizeof(buffer), "%t", "Match Restarting", ChatPrefix0);
	CPrintToChatAll("%t", "Match Restarting", ChatPrefix0);	
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{	
	PrintToServer("%s Round %d was saved", ChatPrefix2, prevRound);
	prevRound += 1;
}

public void GameRestartChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if(!StrEqual(newValue, "0"))
	{	
		restored = false;
		prevRound = 0;

		char buffer[255];
		Format(buffer, sizeof(buffer), "%t", "Starting Game", ChatPrefix0);
		CPrintToChatAll("%t", "Starting Game", ChatPrefix0);		
	}	
}

public int MenuHandler(Menu menu, MenuAction action, int param1, int param2) 
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if (StrEqual(info, "restoreLast"))
		{
			restRound = prevRound - 1;
			VoteRoundMenu(param1, 20);				
		}
		else if (StrEqual(info, "restorePast"))
		{
			VotePast(param1, 20);
		}
		else if (StrEqual(info, "restoreFut"))
		{
			VoteFut(param1, 20);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		char buffer[255];
		Format(buffer, sizeof(buffer), "%t", "Menu Cancelled", ChatPrefix1);
		CPrintToChat(param1, "%t", "Menu Cancelled", ChatPrefix1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action MainMenu(int client, int args)
{
	Menu menu = new Menu(MenuHandler);
	menu.SetTitle("%t", "Round Restore");
	menu.ExitButton = true;
	AddTranslatedMenuItem(menu, "restoreLast", "Restore last Round");
	AddTranslatedMenuItem(menu, "restorePast", "Restore past Rounds");
	if(restored)
	{
		AddTranslatedMenuItem(menu, "restoreFut", "Restore future Rounds");
	}
	menu.Display(client, 20);
	return Plugin_Handled;
}

public int Handle_VoteRound(Menu menu, MenuAction action, int param1,int param2)
{
	if (action == MenuAction_Select) 
	{		
		if (param2 == 0)
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%t", "Voting Successful", ChatPrefix0);
			CPrintToChat(param1, "%t", "Voting Successful", ChatPrefix0);
			restoreRound(restRound);			
		}		
		else if (param2 == 1)
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%t", "Voting Cancelled", ChatPrefix1);
			CPrintToChat(param1, "%t", "Voting Cancelled", ChatPrefix1);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
		{
			int args = 20;
			MainMenu(param1, args);
		}
		else
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%t", "Menu Cancelled", ChatPrefix1);
			CPrintToChat(param1, "%t", "Menu Cancelled", ChatPrefix1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action VoteLast(int client, int args)
{
	restRound = prevRound - 1;
	VoteRoundMenu(client, args);
	return Plugin_Handled;
}

public Action VoteRoundMenu(int client, int args)
{
	Menu menu = new Menu(Handle_VoteRound);
	menu.SetTitle("Restore round %d?", restRound);
	AddTranslatedMenuItem(menu, "yes", "Yes");
	AddTranslatedMenuItem(menu, "no", "No");
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, 20);
	return Plugin_Handled;
}

public int Handle_VoteMultipleRounds(Menu menu, MenuAction action, int param1, int param2)
{	
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));		
		char buffer[255];
		Format(buffer, sizeof(buffer), "%t", "You Selected Round", ChatPrefix0, info);
		CPrintToChat(param1, "%t", "You Selected Round", ChatPrefix0, info);
		restRound = StringToInt(info);
		VoteRoundMenu(param1, 20);
	}
	else if (action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
		{
			int args = 20;
			MainMenu(param1, args);
		}
		else
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%t", "Menu Cancelled", ChatPrefix1);
			CPrintToChat(param1, "%t", "Menu Cancelled", ChatPrefix1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action VotePast(int client, int args)
{
	if (IsVoteInProgress())
	{
		return;
	} 
	Menu menu = new Menu(Handle_VoteMultipleRounds);
	menu.SetTitle("%t", "Which round to restore?", client);
	menu.ExitBackButton = true;
	menu.ExitButton = true;	
	int roundNumber;
	char roundString[8];
	char roundString2[16];
	if(prevRound > 5)
	{
		for(int i = 0; i < 5; i++)
		{	
			roundNumber = prevRound - i - 1;			
			Format(roundString, sizeof(roundString), "%d", roundNumber);
			Format(roundString2, sizeof(roundString2), "%t", "Round %s", roundString);
			menu.AddItem(roundString, roundString2);
		}
	}
	else 
	{
		roundNumber = 0;
		while(roundNumber <= prevRound - 1)
		{
			Format(roundString, sizeof(roundString), "%d", roundNumber);
			Format(roundString2, sizeof(roundString2), "%t", "Round %s", roundString);
			menu.AddItem(roundString, roundString2);
			roundNumber += 1;
		}		
	}
	menu.Display(client, 20);	
}

public Action VoteFut(int client, int args)
{
	if (IsVoteInProgress())
	{
		return;
	} 
	Menu menu = new Menu(Handle_VoteMultipleRounds);
	menu.SetTitle("Which round to restore?");
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	char roundString[8];
	char roundString2[16];
	for(int i = prevRound; i <= prevRound + 4; i++)
	{	
		Format(roundString, sizeof(roundString), "%d", i);
		Format(roundString2, sizeof(roundString2), "%t", "Round %s", roundString);
		menu.AddItem(roundString, roundString2);
	}	
	menu.Display(client, 20);	
}

public Action restoreRound(int round) 
{	
	restored = true;
	prevRound = round;
	char roundName[64];
	char prefix1[1] = "0";
	if(round<10)	
		Format(roundName, sizeof(roundName), "%s%d", prefix1, round);		
	else
		Format(roundName, sizeof(roundName), "%d", round);

	char buffer[255];
	Format(buffer, sizeof(buffer), "%t", "Restoring Round", ChatPrefix0, round);
	CPrintToChatAll("%t", "Restoring Round", ChatPrefix0, round);

	ServerCommand("mp_backup_restore_load_file %s", roundName);	

	char buffer0[255];
	Format(buffer0, sizeof(buffer0), "%t", "Restored Round", ChatPrefix0);
	CPrintToChatAll("%t", "Restored Round", ChatPrefix0);	
	CPrintToChatAll("%s GLHF!", ChatPrefix0);
	return Plugin_Handled;
}

void AddTranslatedMenuItem(Menu menu, const char[] info, const char[] display)
{
	char buffer[128];
	Format(buffer, sizeof(buffer), "%t", display);
	AddMenuItem(menu, info, buffer);
}