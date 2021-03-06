/**
 * vim: set ts=4 :
 * =============================================================================
 * Jetpack Plus
 * Rewrite of the Sourcemod plugin to make it easier to extend and modify.
 *
 * Copyright 2014 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <smlib/entities>
#include <tags>

#define PLUGIN_VERSION "1.2.2"
#define PLUGIN_NAME "Jetpack Plus"

#define JETPACK_TAG "jetpack"

#define MOVECOLLIDE_DEFAULT		0
#define MOVECOLLIDE_FLY_BOUNCE	1

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "Let client's fly around by holding jump.",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_jetpack_plus"
};


new Handle:g_Cvar_Enabled = INVALID_HANDLE;
new Handle:g_Cvar_JetpackForce = INVALID_HANDLE;
new Handle:g_Cvar_JumpDelay = INVALID_HANDLE;

new Handle:g_Forward_OnStartJetpack = INVALID_HANDLE;
new Handle:g_Forward_OnStartJetpackPost = INVALID_HANDLE;
new Handle:g_Forward_OnStopJetpack = INVALID_HANDLE;
new Handle:g_Forward_OnStopJetpackPost = INVALID_HANDLE;
new Handle:g_Forward_OnJetpackStep= INVALID_HANDLE;

new bool:g_IsUsingJetpack[MAXPLAYERS+1] = {false, ...};
new bool:g_AdvertShown[MAXPLAYERS+1] = {false, ...};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    if (LibraryExists("jetpack_plus"))
    {
        strcopy(error, err_max, "Jetpack Plus already loaded, aborting.");
        return APLRes_Failure;
    }

    RegPluginLibrary("jetpack_plus"); 

    CreateNative("IsClientUsingJetpack", _IsClientUsingJetpack);
    CreateNative("AreJetpacksEnabled", _AreJetpacksEnabled);

    return APLRes_Success;
}

public OnPluginStart()
{
    LoadTranslations("jetpack_plus.phrases");

    CreateConVar("sm_jetpack_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_Cvar_Enabled = CreateConVar(
            "sm_jetpack",
            "1",
            "Set to 1 to enable the jetpack plugin",
            FCVAR_PLUGIN | FCVAR_REPLICATED | FCVAR_NOTIFY,
            true,
            0.0,
            true,
            1.0);
    g_Cvar_JetpackForce = CreateConVar(
            "sm_jetpack_force",
            "8.0",
            "Strength at which the jetpack pushes the player"
            );
    g_Cvar_JumpDelay = CreateConVar(
            "sm_jetpack_jump_delay",
            "0.15",
            "The time in seconds the jump key needs to be pressed before the jetpack starts"
            );

    
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookConVarChange(g_Cvar_Enabled, OnEnabledChange);
    AddServerTag3(JETPACK_TAG);

    g_Forward_OnStartJetpack     = CreateGlobalForward("OnStartJetpack", ET_Event, Param_Cell);
    g_Forward_OnStartJetpackPost = CreateGlobalForward("OnStartJetpackPost", ET_Ignore, Param_Cell);
    g_Forward_OnStopJetpack      = CreateGlobalForward("OnStopJetpack",  ET_Event, Param_Cell);
    g_Forward_OnStopJetpackPost  = CreateGlobalForward("OnStopJetpackPost",  ET_Ignore, Param_Cell);
    g_Forward_OnJetpackStep      = CreateGlobalForward("OnJetpackStep",  ET_Event, Param_Cell, Param_FloatByRef, Param_CellByRef);
}

public OnPluginEnd()
{
    RemoveServerTag3(JETPACK_TAG);
}

public OnClientConnected(client)
{
    g_AdvertShown[client] = false;
}

public OnClientDisconnect(client)
{
    if(AreJetpacksEnabled())
    {
        StopJetpack(client);
    }
}

public OnGameFrame()
{
    if(AreJetpacksEnabled())
    {
        StepAllJetpacks();
    }
}

public OnEnabledChange(Handle:cvar, const String:oldValue[], const String:newValue[])
{
    if(cvar != g_Cvar_Enabled) return;

    new bool:was_on = !!StringToInt(oldValue);
    new bool:now_on = !!StringToInt(newValue);

    //When changing from on to off
    if(was_on && !now_on)
    {
        StopAllJetpacks();
        RemoveServerTag3(JETPACK_TAG);
    }

    //When changing from off to on
    if(!was_on && now_on)
    {
        AddServerTag3(JETPACK_TAG);
        PrintToChatAll("\x04%t", "jetpack_enabled_on_server");
    }
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2])
{
    if(!AreJetpacksEnabled()) return Plugin_Continue;

    if(!IsClientUsingJetpack(client) && buttons & IN_JUMP)
    {
        new player = GetClientUserId(client);
        new Float:delay = GetConVarFloat(g_Cvar_JumpDelay);
        CreateTimer(delay, HeldJump, player);
    }

    return Plugin_Continue;
}

//Call back for when a player presses jump.  Checks if jump is still held down
public Action:HeldJump(Handle:timer, any:player)
{
    new client = GetClientOfUserId(player);

    if(client <= 0) return Plugin_Handled;
    if(!IsClientInGame(client)) return Plugin_Handled;
    if(!IsPlayerAlive(client)) return Plugin_Handled;
    if(!AreJetpacksEnabled()) return Plugin_Handled;

    if(!IsClientUsingJetpack(client) && GetClientButtons(client) & IN_JUMP)
    {
        StartJetpack(client);
    }

    return Plugin_Handled;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));

    if(g_AdvertShown[client] || !IsClientInGame(client) || !AreJetpacksEnabled()) return;

    PrintToChat(client, "\x04%t", "jetpack_enabled_on_server");
    g_AdvertShown[client] = true;
}

public _IsClientUsingJetpack(Handle:plugin, args) { return _:IsClientUsingJetpack(GetNativeCell(1)); }
bool:IsClientUsingJetpack(client)
{
    return g_IsUsingJetpack[client];
}

public _AreJetpacksEnabled(Handle:plugin, args) { return _:AreJetpacksEnabled(); }
bool:AreJetpacksEnabled()
{
    return GetConVarBool(g_Cvar_Enabled);
}

StartJetpack(client)
{
    //Forward event
    decl Action:result;
    Call_StartForward(g_Forward_OnStartJetpack);
    Call_PushCell(client);
    Call_Finish(result);
    if(result == Plugin_Handled) return;

    SetEntityMoveType(client, MOVETYPE_FLY);
    SetEntityMoveCollide(client, MOVECOLLIDE_FLY_BOUNCE);
    ChangeEdictState(client);
    g_IsUsingJetpack[client] = true;

    //Forward post event
    Call_StartForward(g_Forward_OnStartJetpackPost);
    Call_PushCell(client);
    Call_Finish();
}

StopJetpack(client)
{
    //Forward event
    decl Action:result;
    Call_StartForward(g_Forward_OnStopJetpack);
    Call_PushCell(client);
    Call_Finish(result);
    if(result == Plugin_Handled) return;

    if(IsClientInGame(client))
    {
        SetEntityMoveType(client, MOVETYPE_WALK);
        SetEntityMoveCollide(client, MOVECOLLIDE_DEFAULT);
        ChangeEdictState(client);
    }
    g_IsUsingJetpack[client] = false;

    //Forward post event
    Call_StartForward(g_Forward_OnStopJetpackPost);
    Call_PushCell(client);
    Call_Finish();
}

//Called each frame a client is using a jetpack
JetpackStep(client)
{
    new Float:force = GetConVarFloat(g_Cvar_JetpackForce);
    new bool:force_stop = false;

    //Forward event
    decl Action:result;
    Call_StartForward(g_Forward_OnJetpackStep);
    Call_PushCell(client);
    Call_PushFloatRef(force);
    Call_PushCellRef(force_stop);
    Call_Finish(result);
    if(result == Plugin_Handled) return;

    new buttons = GetClientButtons(client);
    if(!force_stop && IsPlayerAlive(client) && (buttons & IN_JUMP))
    {
        JetpackPush(client, force);
    }
    else
    {
        StopJetpack(client);
    }
}

StepAllJetpacks()
{
    for (new client=1; client <= MaxClients; client++)
    {
        //For each client using a jetpack
        if(IsClientUsingJetpack(client))
        {
            JetpackStep(client);
        }
    }
}

StopAllJetpacks()
{
    for (new client=1; client <= MaxClients; client++)
    {
        //For each client using a jetpack
        if(IsClientUsingJetpack(client))
        {
            StopJetpack(client);
        }
    }
}

JetpackPush(client, Float:force)
{
    new Float:vec[3];
    Entity_GetBaseVelocity(client, vec);
    vec[2] += force;
    Entity_SetBaseVelocity(client, vec);
    ChangeEdictState(client);
}

SetEntityMoveCollide(entity, movecollide)
{
    SetEntProp(entity, Prop_Data, "m_MoveCollide", movecollide);
}
