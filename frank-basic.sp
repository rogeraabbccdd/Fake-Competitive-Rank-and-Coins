#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.2"

bool g_bIsCoin[MAXPLAYERS+1];
bool g_bIsProfileRank[MAXPLAYERS+1];

int g_iRank[MAXPLAYERS+1] = {0,...};
int g_iProfileRank[MAXPLAYERS+1] = {0,...};
int g_iCoin[MAXPLAYERS+1] = {0,...};

char g_section[64];
int g_array;

Handle g_cookieRank = INVALID_HANDLE;
Handle g_cookieProfileRank = INVALID_HANDLE;
Handle g_cookieCoin = INVALID_HANDLE;

Handle g_arrayRanks = INVALID_HANDLE;
Handle g_arrayProfileRanks = INVALID_HANDLE;
Handle g_arrayCoins = INVALID_HANDLE;
Handle g_arrayRanksNum = INVALID_HANDLE;
Handle g_arrayProfileRanksNum = INVALID_HANDLE;
Handle g_arrayCoinsNum = INVALID_HANDLE;

Handle kv = INVALID_HANDLE;

ConVar g_hCvarVersion;
ConVar g_ShowCoins;
ConVar g_ShowProfileRanks;

public Plugin myinfo = {
	name = "[CS:GO] Fake Competitive Ranks/Coins",
	author = "Laam4",
	description = "Show competitive ranks and coins on scoreboard",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=2265799"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("frank.phrases");
	
	g_hCvarVersion = CreateConVar("sm_frank_version", PLUGIN_VERSION, "Fake rank version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hCvarVersion.SetString(PLUGIN_VERSION);
	g_ShowCoins = CreateConVar("sm_frank_coins", "1", "Show legit coins on players, if enabled", _, true, 0.0, true, 1.0);
	g_ShowProfileRanks = CreateConVar("sm_frank_profileranks", "1", "Show legit profile ranks on players, if enabled", _, true, 0.0, true, 1.0);
	
	RegAdminCmd("sm_elorank", Command_SetElo,  ADMFLAG_GENERIC, "sm_elorank <#userid|name> <0-18>");
	RegAdminCmd("sm_emblem", Command_SetCoin, ADMFLAG_GENERIC, "sm_emblem <#userid|name> <874-6011>");
	RegAdminCmd("sm_prorank", Command_SetProfile,  ADMFLAG_GENERIC, "sm_prorank <#userid|name> <0-40>");
	
	RegConsoleCmd("sm_coin", Command_CoinMenu);
	RegConsoleCmd("sm_mm", Command_EloMenu);
	RegConsoleCmd("sm_profile", Command_ProfileMenu);
	
	AutoExecConfig(true, "frank");
	
	HookEvent("announce_phase_end", Event_AnnouncePhaseEnd);
	HookEvent("player_disconnect", Event_Disconnect, EventHookMode_Pre);
	//HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre); 
	g_cookieRank = RegClientCookie("g_iRank", "", CookieAccess_Private);
	g_cookieProfileRank = RegClientCookie("g_iProfileRank", "", CookieAccess_Private);
	g_cookieCoin = RegClientCookie("g_iCoin", "", CookieAccess_Private);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i))
		{
			OnClientCookiesCached(i);
		}
	}
}

public void OnMapStart()
{
	int iIndex = FindEntityByClassname(MaxClients+1, "cs_player_manager");
	if (iIndex == -1)
	{
		SetFailState("Unable to find cs_player_manager entity");
	}
	SDKHook(iIndex, SDKHook_ThinkPost, Hook_OnThinkPost);
	
	char configFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configFile, sizeof(configFile), "configs/frank.cfg");

	if (!FileExists(configFile))
	{
		LogError("The frank config (%s) file does not exist", configFile);
		return;
	}

	kv = CreateKeyValues("Frank");
	FileToKeyValues(kv, configFile);
	if (!KvGotoFirstSubKey(kv))
	{
		LogError("The frank config (%s) file was empty", configFile);
		return;
	}
	
	g_arrayRanks = CreateArray(ByteCountToCells(64));
	g_arrayProfileRanks = CreateArray(ByteCountToCells(64));
	g_arrayCoins = CreateArray(ByteCountToCells(64));

	g_arrayRanksNum = CreateArray();
	g_arrayProfileRanksNum = CreateArray();
	g_arrayCoinsNum = CreateArray();

	BrowseKeyValues(kv);
}
	
void BrowseKeyValues(Handle k)
{
	char key[64];
	char value[64];
	do
	{
		// You can read the section/key name by using KvGetSectionName here.
		KvGetSectionName(k, g_section, sizeof(g_section));
		if (StrEqual(g_section, "Ranks"))
		{
			g_array = 1;
			//LogToGame("Array 1");
		}
		if (StrEqual(g_section, "Profile"))
		{
			g_array = 2;
			//LogToGame("Array 2");
		}
		if (StrEqual(g_section, "Coins"))
			{
			g_array = 3;
			//LogToGame("Array 3");
		}
		//LogToGame("section: %s", g_section);
		if (KvGotoFirstSubKey(k, false))
		{
			// Current key is a section. Browse it recursively.
			//LogToGame("Recursive");
			BrowseKeyValues(k);
			KvGoBack(k);
		}
		else
		{
			// Current key is a regular key, or an empty section.
			if (KvGetDataType(k, NULL_STRING) != KvData_None)
			{
				KvGetSectionName(k, key, sizeof(key));
				KvGetString(k, NULL_STRING, value, sizeof(value));
				//LogToGame("%d: key: %s | value: %s", g_array, key, value);
				switch(g_array)
				{
					case 1:
					{
						PushArrayString(g_arrayRanks, value);
						PushArrayCell(g_arrayRanksNum, StringToInt(key));
					}
					case 2:
					{
						PushArrayString(g_arrayProfileRanks, value);
						PushArrayCell(g_arrayProfileRanksNum, StringToInt(key));
					}
					case 3:
					{
						PushArrayString(g_arrayCoins, value);
						PushArrayCell(g_arrayCoinsNum, StringToInt(key));
					}
				}
			}
		}
	} while (KvGotoNextKey(k, false));
}

public void OnClientCookiesCached(int client)
{
	char valueRank[16];
	char valueProfileRank[16];
	char valueCoin[16];
	GetClientCookie(client, g_cookieRank, valueRank, sizeof(valueRank));
	if(strlen(valueRank) > 0) g_iRank[client] = StringToInt(valueRank);
	GetClientCookie(client, g_cookieProfileRank, valueProfileRank, sizeof(valueProfileRank));
	if(strlen(valueProfileRank) > 0)
	{
		g_iProfileRank[client] = StringToInt(valueProfileRank);
		g_bIsProfileRank[client] = true;
	}
	GetClientCookie(client, g_cookieCoin, valueCoin, sizeof(valueCoin));
	if(strlen(valueCoin) > 0)
	{
		g_iCoin[client] = StringToInt(valueCoin);
		g_bIsCoin[client] = true;
	}
}
	
public Action Event_Disconnect(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client)
	{
		g_iCoin[client] = 0;
		g_iRank[client] = 0;
		g_iProfileRank[client] = 0;
		g_bIsCoin[client] = false;
		g_bIsProfileRank[client] = false;
	}
}
/*
public Action Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast) 
{ 
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client)
	{	
		g_iRank[client] = 0;
	}
}
*/
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (buttons & IN_SCORE && !(GetEntProp(client, Prop_Data, "m_nOldButtons") & IN_SCORE)) {
		Handle hBuffer = StartMessageOne("ServerRankRevealAll", client);
		if (hBuffer == INVALID_HANDLE)
		{
			PrintToChat(client, "INVALID_HANDLE");
		}
		else
		{
			EndMessage();
		}
	}
	return Plugin_Continue;
}

public Action Event_AnnouncePhaseEnd(Handle event, const char[] name, bool dontBroadcast)
{
	Handle hBuffer = StartMessageAll("ServerRankRevealAll");
	if (hBuffer == INVALID_HANDLE)
	{
		PrintToServer("ServerRankRevealAll = INVALID_HANDLE");
	}
	else
	{
		EndMessage();
	}
	return Plugin_Continue;
}

public void Hook_OnThinkPost(int iEnt)
{
	int Offset[3] = {-1, -1, -1};
	if (Offset[0] == -1)
	{
		Offset[0] = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRanking");
	}
	if (Offset[1] == -1)
	{
		Offset[1] = FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel");
	}
	if (Offset[2] == -1)
	{
		Offset[2] = FindSendPropInfo("CCSPlayerResource", "m_nActiveCoinRank");
	}

	SetEntDataArray(iEnt, Offset[0], g_iRank, MAXPLAYERS+1, _, true);
	
	if (GetConVarBool(g_ShowProfileRanks))
	{
		int tempPrank[MAXPLAYERS+1];
		GetEntDataArray(iEnt, Offset[1], tempPrank, MAXPLAYERS+1);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bIsProfileRank[i])
			{
				tempPrank[i] = g_iProfileRank[i];
			}
		}
		SetEntDataArray(iEnt, Offset[1], tempPrank, MAXPLAYERS+1, _, true);
	} else {
		SetEntDataArray(iEnt, Offset[1], g_iProfileRank, MAXPLAYERS+1, _, true);
	}
	
	if (GetConVarBool(g_ShowCoins))
	{
		int tempCoin[MAXPLAYERS+1];
		GetEntDataArray(iEnt, Offset[2], tempCoin, MAXPLAYERS+1);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bIsCoin[i])
			{
				tempCoin[i] = g_iCoin[i];
			}
		}
		SetEntDataArray(iEnt, Offset[2], tempCoin, MAXPLAYERS+1, _, true);
	} else {
		SetEntDataArray(iEnt, Offset[2], g_iCoin, MAXPLAYERS+1, _, true);
	}
}

public Action Command_EloMenu(int client, int args)
{
	if (IsClientInGame(client))
	{
		Menu elo = CreateMenu(EloHandler);
		elo.SetTitle("%T", "Rank_Menu", client);
		int size = GetArraySize(g_arrayRanks);
		int key[64];
		char ckey[64];
		char value[64];
		for (int i = 0; i < size; i++)
		{
			key[i] = GetArrayCell(g_arrayRanksNum, i);
			IntToString(key[i], ckey, sizeof(ckey));
			GetArrayString(g_arrayRanks, i, value, sizeof(value));
			elo.AddItem(ckey, value);		
		}			
		elo.Display(client, 30);
	}
	return Plugin_Handled;
}

public int EloHandler(Menu elo, MenuAction action, int client, int itemNum)
{
	switch(action)
	{
	case MenuAction_Select:
		{
			char info[4];
			char rankName[64];
			int index;
			elo.GetItem(itemNum, info, sizeof(info));
			g_iRank[client] = StringToInt(info);
			SetClientCookie(client, g_cookieRank, info);
			index = FindValueInArray(g_arrayRanksNum, g_iRank[client]);
			GetArrayString(g_arrayRanks, index, rankName, sizeof(rankName));
			PrintToChat(client, "%T\x06%s", "Rank_Set", client, rankName);
		}
	case MenuAction_End:
		{
			delete elo;
		}
	}
}

public Action Command_ProfileMenu(int client, int args)
{
	if (IsClientInGame(client))
	{
		Menu profile = CreateMenu(ProfileHandler);
		profile.SetTitle("%T", "ProfileRank_Menu", client);
		int size = GetArraySize(g_arrayProfileRanks);
		int key[64];
		char ckey[64];
		char value[64];
		for (int i = 0; i < size; i++)
		{
			key[i] = GetArrayCell(g_arrayProfileRanksNum, i);
			IntToString(key[i], ckey, sizeof(ckey));
			GetArrayString(g_arrayProfileRanks, i, value, sizeof(value));
			profile.AddItem(ckey, value);		
		}			
		profile.Display(client, 30);
	}
	return Plugin_Handled;
}

public int ProfileHandler(Menu profile, MenuAction action, int client, int itemNum)
{
	switch(action)
	{
	case MenuAction_Select:
		{
			char info[4];
			char prankName[64];
			int index;
			profile.GetItem(itemNum, info, sizeof(info));
			g_iProfileRank[client] = StringToInt(info);
			SetClientCookie(client, g_cookieProfileRank, info);
			g_bIsProfileRank[client] = true;
			index = FindValueInArray(g_arrayProfileRanksNum, g_iProfileRank[client]);
			GetArrayString(g_arrayProfileRanks, index, prankName, sizeof(prankName));
			PrintToChat(client, "%T\x06%s", "ProfileRank_Set", client, prankName);
		}
	case MenuAction_End:
		{
			delete profile;
		}
	}
}

public Action Command_CoinMenu(int client, int args)
{
	if (IsClientInGame(client))
	{
		Menu coin = CreateMenu(CoinHandler);
		coin.SetTitle("%T", "Coin_Menu", client);
		int size = GetArraySize(g_arrayCoins);
		int key[999];
		char ckey[999];
		char value[999];
		for (int i = 0; i < size; i++)
		{
			key[i] = GetArrayCell(g_arrayCoinsNum, i);
			IntToString(key[i], ckey, sizeof(ckey));
			GetArrayString(g_arrayCoins, i, value, sizeof(value));
			coin.AddItem(ckey, value);		
		}			
		coin.Display(client, 30);
	}
	return Plugin_Handled;
}

public int CoinHandler(Menu coin, MenuAction action, int client, int itemNum)
{
	switch(action)
	{
	case MenuAction_Select:
		{
			char info[6];
			char coinName[999];
			int index;
			coin.GetItem(itemNum, info, sizeof(info));
			g_iCoin[client] = StringToInt(info);
			SetClientCookie(client, g_cookieCoin, info);
			g_bIsCoin[client] = true;
			index = FindValueInArray(g_arrayCoinsNum, g_iCoin[client]);
			GetArrayString(g_arrayCoins, index, coinName, sizeof(coinName));
			PrintToChat(client, "%T\x06%s", "Coin_Set", client, coinName);
		}
	case MenuAction_End:
		{
			delete coin;
		}
	}
}

public Action Command_SetElo(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_elorank <#userid|name> <0-18>");
		return Plugin_Handled;
	}
	
	char szTarget[65];
	GetCmdArg(1, szTarget, sizeof(szTarget));

	char szTargetName[MAX_TARGET_LENGTH+1];
	int iTargetList[MAXPLAYERS+1];
	int iTargetCount;
	bool bTnIsMl;

	if ((iTargetCount = ProcessTargetString(
					szTarget,
					client,
					iTargetList,
					MAXPLAYERS,
					COMMAND_FILTER_CONNECTED,
					szTargetName,
					sizeof(szTargetName),
					bTnIsMl)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	char szRank[6];
	GetCmdArg(2, szRank, sizeof(szRank));

	int iRanks = StringToInt(szRank);
	
	for (int i = 0; i < iTargetCount; i++)
	{
		g_iRank[iTargetList[i]] = iRanks;
		SetClientCookie(iTargetList[i], g_cookieRank, szRank);
	}
	
	return Plugin_Handled;
}

public Action Command_SetProfile(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_prorank <#userid|name> <0-40>");
		return Plugin_Handled;
	}
	
	char szTarget[65];
	GetCmdArg(1, szTarget, sizeof(szTarget));

	char szTargetName[MAX_TARGET_LENGTH+1];
	int iTargetList[MAXPLAYERS+1];
	int iTargetCount;
	bool bTnIsMl;

	if ((iTargetCount = ProcessTargetString(
					szTarget,
					client,
					iTargetList,
					MAXPLAYERS,
					COMMAND_FILTER_CONNECTED,
					szTargetName,
					sizeof(szTargetName),
					bTnIsMl)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	char szRank[6];
	GetCmdArg(2, szRank, sizeof(szRank));

	int iRanks = StringToInt(szRank);
	
	for (int i = 0; i < iTargetCount; i++)
	{
		g_iProfileRank[iTargetList[i]] = iRanks;
		g_bIsProfileRank[iTargetList[i]] = true;
		SetClientCookie(iTargetList[i], g_cookieProfileRank, szRank);
	}
	
	return Plugin_Handled;
}

public Action Command_SetCoin(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_emblem <#userid|name> <coin>");
		return Plugin_Handled;
	}
	
	char szTarget[65];
	GetCmdArg(1, szTarget, sizeof(szTarget));

	char szTargetName[MAX_TARGET_LENGTH+1];
	int iTargetList[MAXPLAYERS+1];
	int iTargetCount;
	bool bTnIsMl;

	if ((iTargetCount = ProcessTargetString(
					szTarget,
					client,
					iTargetList,
					MAXPLAYERS,
					COMMAND_FILTER_CONNECTED,
					szTargetName,
					sizeof(szTargetName),
					bTnIsMl)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	char szCoin[6];
	GetCmdArg(2, szCoin, sizeof(szCoin));

	int g_iCoins = StringToInt(szCoin);
	
	for (int i = 0; i < iTargetCount; i++)
	{
		g_iCoin[iTargetList[i]] = g_iCoins;
		g_bIsCoin[iTargetList[i]] = true;
		SetClientCookie(iTargetList[i], g_cookieCoin, szCoin);
	}
	return Plugin_Handled;
}
