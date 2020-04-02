// Notes about scripts
//=====================
//
// Anim variables
// -------------- 
// Anim variables keep track of what the character is doing with respect to his 
// animations.  They know if he's standing, crouching, kneeling, walking, running, etc, 
// so that he can play appropriate transitions to get to the animation he wants.
// anim_movement - "stop", "walk", "run"
// anim_pose - "stand", "crouch", some others for pain poses.
// I'm putting functions to do the basic animations to change these variables in 
// zombie_SetPoseMovement.gsc, 
//
// Error Reporting
// ---------------
// To report a script error condition (similar to assert(0)), I assign a non-existent variable to 
// the variable homemade_error  I use the name of the non-existent variable to try to explain the 
// error.  For example:
// 		homemade_error = Unexpected_anim_pose_value + self.a.pose;
// I also have a kind of assert, called as follows:
//		[[anim.assertEX(condition, message_string);
// If condition evaluates to 0, the assert fires, prints message_string and stops the server. Since 
// I don't have stack traces of any kind, the message string needs to say from where the assert was 
// called.

#include animscripts\zombie_utility;
#include maps\_utility;
#include animscripts\Combat_utility;
#include common_scripts\Utility;

#using_animtree ("generic_human");

main()
{
	prof_begin("animscript_init");
	self.a = SpawnStruct();

	self.root_anim = %root;
	
	self thread beginGrenadeTracking();
	
	firstInit();

	anim.reacquireNum--;
	if (anim.reacquireNum <= 0 && self.team == "axis")
	{
		anim.reacquireNum = 1;
     	self.a.reacquireGuy = true;
    }
	else
	{
     	self.a.reacquireGuy = false;
	}
		
	// Set initial states for poses
	self.a.pose = "stand";
	self.a.movement = "stop";
	self.a.state = "stop";
	self.a.special = "none";

	self.a.combatEndTime = GetTime();
	self.a.script = "init";
	self.a.alertness = "casual"; // casual, alert, aiming
	self.a.lastEnemyTime = GetTime();
	self.a.forced_cover = "none";
	self.a.desired_script = "none";
	self.a.current_script = "none";
	self.a.disableLongDeath = self.team != "axis";
	self.a.lookangle = 0;
	self.a.painTime = 0;
	self.a.nextGrenadeTryTime = 0;
	
	// setup the speed variables
	self.walk			= false;
	self.sprint			= false;
	
	// WW (11/16/2010): Setting variable for run blend speed. This allows the black hole bomb to snap guys 180 with less pop.
	self.a.runBlendTime = 0.2;
	
	// MikeD (9/28/2007): Flame pain time... Tracks when the AI gets hit with flame.
	self.a.flamepainTime = 0;
	
	self.a.postScriptFunc = undefined;
	self.a.stance = "stand";
	
	self._animActive = 0;
	self._lastAnimTime = 0;
	
	self thread deathNotify();

	// use the GDT settings to start with
	self.baseAccuracy = self.accuracy;

	// set default accuracy mod
	if( !IsDefined(self.script_accuracy) )
	{
		self.script_accuracy = 1;
	}
	
	// scale baseAccuracy based on number of coop players
	if (self.team == "axis")
	{
		self thread maps\_gameskill::axisAccuracyControl();
	}
	else if (self.team == "allies")
	{
		self thread maps\_gameskill::alliesAccuracyControl();
	}
		
	self.a.missTime = 0;
	
	self.a.yawTransition = "none";
	self.a.nodeath = false;
	self.a.missTime = 0;
	self.a.missTimeDebounce = 0;
	self.a.disablePain = false;

	self.accuracyStationaryMod = 1;
	self.chatInitialized = false;
	self.sightPosTime = 0;
	self.sightPosLeft = true;
	self.preCombatRunEnabled = true;
	self.is_zombie = true;

	self.a.grenadeFlee = animscripts\zombie_run::GetRunAnim();
	
	self.a.crouchpain = false; // for dying pain guys
	self.a.nextStandingHitDying = false;
	anim_set_next_move_to_new_cover();
	

	// Makes AI able to throw grenades at other AI.
	if (!IsDefined (self.script_forcegrenade))
	{
		self.script_forcegrenade = 0;
	}

/#
	self.a.lastDebugPrint = "";
#/
	self.a.StopCowering = ::DoNothing;
	
	SetupUniqueAnims();

/#
	thread animscripts\debug::UpdateDebugInfo();
#/

	// state tracking
	self.lastEnemySightTime = 0; // last time we saw our current enemy
	self.combatTime = 0; // how long we've been in/out of combat
	
	// Random range makes the grenades less accurate and do less damage, but also makes it difficult to throw back.
	if ( self.team == "allies" )
	{
		self.randomGrenadeRange = 0;
	}
	else
	{
		self.randomGrenadeRange = 128;
	}

	self.ramboChance = 0;

	if (self.team == "axis")
	{
		self.ramboChance *= 2;
	}

    self.coverIdleSelectTime = -696969;
    self.exception = [];
    
    self.exception[ "corner" ] = 1;
    self.exception[ "cover_crouch" ] = 1;
    self.exception[ "stop" ] = 1;
    self.exception[ "stop_immediate" ] = 1;
    self.exception[ "move" ] = 1;
    self.exception[ "exposed" ] = 1;
    self.exception[ "corner_normal" ] = 1;

	keys = getArrayKeys( self.exception );
	for ( i=0; i < keys.size; i++ )
	{
		clear_exception( keys[ i ] );
	}
	
	self.old = SpawnStruct();
	
	self.reacquire_state = 0;
	
	self thread setNameAndRank();
	
	self.shouldConserveAmmoTime = 0;
	
	/#
	self thread printEyeOffsetFromNode();
	self thread showLikelyEnemyPathDir();
	#/
	
	self thread onDeath();

	self.a.allow_shooting					= false;

	prof_end("animscript_init");
}

/#
printEyeOffsetFromNode()
{
	self endon("death");

	while(1)
	{
		debug_replay("File: init.gsc. Function: printEyeOffsetFromNode() - INNER LOOP START\n");
	
		if ( GetDvarInt( #"scr_eyeoffset") == self getentnum() )
		{
			if ( IsDefined( self.coverNode ) )
			{
				offset = self geteye() - self.coverNode.origin;
				forward = AnglesToForward(self.coverNode.angles);
				right = AnglesToRight(self.coverNode.angles);
				trueoffset = (vectordot(right, offset), vectordot(forward, offset), offset[2]);
				println( trueoffset );
			}
		}
		else
		{
			wait 2;
		}
			
		debug_replay("File: init.gsc. Function: printEyeOffsetFromNode() - INNER LOOP STOP\n");
		
		wait .1;
	}
}

showLikelyEnemyPathDir()
{
	debug_replay("File: init.gsc. Function: showLikelyEnemyPathDir()\n");
	
	self endon("death");

	if ( GetDvar( #"scr_showlikelyenemypathdir") == "" )
	{
		SetDvar( "scr_showlikelyenemypathdir", "-1" );
	}

	while(1)
	{
		debug_replay("File: init.gsc. Function: showLikelyEnemyPathDir() - INNER LOOP START\n");
	
		if ( GetDvarInt( #"scr_showlikelyenemypathdir") == self getentnum() )
		{
			yaw = self.angles[1];
			dir = self getAnglesToLikelyEnemyPath();
		
			if ( IsDefined( dir ) )
			{
				yaw = dir[1];
			}

			printpos = self.origin + (0,0,60) + AnglesToForward((0,yaw,0)) * 100;
			line( self.origin + (0,0,60), printpos );

			if ( IsDefined( dir ) )
			{
				Print3d( printpos, "likelyEnemyPathDir: " + yaw, (1,1,1), 1, 0.5 );
			}
			else
			{
				Print3d( printpos, "likelyEnemyPathDir: undefined", (1,1,1), 1, 0.5 );
			}
			
			debug_replay("File: init.gsc. Function: showLikelyEnemyPathDir() - INNER LOOP START WAIT .05\n");
			
			wait .05;
			
			debug_replay("File: init.gsc. Function: showLikelyEnemyPathDir() - INNER LOOP STOP WAIT .05\n");
		}
		else
		{
			wait 2;
		}
	
		debug_replay("File: init.gsc. Function: showLikelyEnemyPathDir() - INNER LOOP STOP\n");
	}

	debug_replay("File: init.gsc. Function: showLikelyEnemyPathDir() - COMPLETE\n");
}
#/

setNameAndRank()
{
	self endon ( "death" );

	if (!IsDefined (level.loadoutComplete))
	{
		level waittill ("loadout complete");
	}

	self maps\_names::get_name();
}

DoNothing()
{
}

SetupUniqueAnims()
{
	if ( !IsDefined( self.animplaybackrate ) || !IsDefined( self.moveplaybackrate ) )
	{
		set_anim_playback_rate();
	}
}

set_anim_playback_rate()
{
	self.animplaybackrate = 0.9 + RandomFloat( 0.2 );
	self.moveplaybackrate = 1; 
}


infiniteLoop(one, two, three, whatever)
{
	/#
	debug_replay("File: init.gsc. Function: infiniteLoop() - START WAIT FOR new exceptions\n");
	#/
	
	anim waittill("new exceptions");
	
	/#
	debug_replay("File: init.gsc. Function: infiniteLoop() - STOP WAIT FOR new exceptions\n");
	#/
}

empty(one, two, three, whatever)
{
}

clearEnemy()
{
	self notify ("stop waiting for enemy to die");
	self endon ("stop waiting for enemy to die");
	self.sightEnemy waittill ("death");
	self.sightpos = undefined;
	self.sightTime = 0;
	self.sightEnemy = undefined;
}

previewSightPos()
{
	/#
	self endon ("death");

	for (;;)
	{
		debug_replay("File: init.gsc. Function: previewSightPos() - INNER LOOP START\n");
		
		if (GetDebugDvar ("debug_lastsightpos") != "on")
		{
			wait (1);
			continue;
		}
		
		wait (0.05);

		if (!IsDefined(self.lastEnemySightPos))
		{
			continue;
		}

		Print3d (self.lastEnemySightPos, "X", (0.2,0.5,1.0), 1, 1.0);	// origin, text, RGB, alpha, scale

		debug_replay("File: init.gsc. Function: previewSightPos() - INNER LOOP END\n");
	}
	#/
}

previewAccuracy()
{
	/#
	if (!IsDefined (level.offsetNum))
	{
		level.offsetNum = 0;
	}
		
	offset = 1;
	level.offsetNum++;
	if (level.offsetNum > 5)
	{
		level.offsetNum = 1;
	}

	self endon ("death");

	for (;;)
	{
		if (GetDebugDvar("debug_accuracypreview") != "on")
		{
			wait (1);
			continue;
		}
		
		wait (0.05);
		Print3d (self.origin + (0,0,70 + 25*offset ), self.accuracy, (0.2,0.5,1.0), 1, 1.15);
	}
	#/
}

trackVelocity()
{
	self endon ("death");

	for (;;)
	{
		self.oldOrigin = self.origin;
		wait (0.2);
	}
}

// Cleans up scripts on death
deathNotify()
{
	self waittill( "death", other );
	self notify( anim.scriptChange );
}

setupHats()
{
	anim.noHat = []; // tracks which models arent meant to have detachable hats.		
	addNoHat("character_british_africa_price");
	addNoHat("character_british_normandy_price");
	addNoHat("character_british_normandy_price");
	addNoHat("character_german_winter_masked_dark");
	addNoHat("character_russian_trench_d");

	anim.noHatClassname = []; // tracks which models arent meant to have detachable hats.		
	addNoHatClassname("actor_ally_rus_volsky");

	anim.metalHat = []; // tracks which models arent meant to have detachable hats.		
	addMetalHat("character_british_duhoc_driver");
	addMetalHat("character_us_ranger_cpl_a");
	addMetalHat("character_us_ranger_lt_coffey");
	addMetalHat("character_us_ranger_medic_wells");
	addMetalHat("character_us_ranger_pvt_a");
	addMetalHat("character_us_ranger_pvt_a_low");
	addMetalHat("character_us_ranger_pvt_a_wounded");
	addMetalHat("character_us_ranger_pvt_b");
	addMetalHat("character_us_ranger_pvt_b_low");
	addMetalHat("character_us_ranger_pvt_b_wounded");
	addMetalHat("character_us_ranger_pvt_braeburn");
	addMetalHat("character_us_ranger_pvt_c");
	addMetalHat("character_us_ranger_pvt_c_low");
	addMetalHat("character_us_ranger_pvt_d");
	addMetalHat("character_us_ranger_pvt_d_low");
	addMetalHat("character_us_ranger_pvt_mccloskey");
	addMetalHat("character_us_ranger_radio");
	addMetalHat("character_us_ranger_sgt_randall");
	addMetalHat("character_us_wet_ranger_cpl_a");
	addMetalHat("character_us_wet_ranger_lt_coffey");
	addMetalHat("character_us_wet_ranger_medic_wells");
	addMetalHat("character_us_wet_ranger_pvt_a");
	addMetalHat("character_us_wet_ranger_pvt_a_low");
	addMetalHat("character_us_wet_ranger_pvt_a_wounded");
	addMetalHat("character_us_wet_ranger_pvt_b");
	addMetalHat("character_us_wet_ranger_pvt_b_low");
	addMetalHat("character_us_wet_ranger_pvt_b_wounded");
	addMetalHat("character_us_wet_ranger_pvt_braeburn");
	addMetalHat("character_us_wet_ranger_pvt_c");
	addMetalHat("character_us_wet_ranger_pvt_c_low");
	addMetalHat("character_us_wet_ranger_pvt_d");
	addMetalHat("character_us_wet_ranger_pvt_d_low");
	addMetalHat("character_us_wet_ranger_pvt_mccloskey");
	addMetalHat("character_us_wet_ranger_radio");
	addMetalHat("character_us_wet_ranger_sgt_randall");
	addMetalHat("character_british_afrca_body");
	addMetalHat("character_british_afrca_body_low");
	addMetalHat("character_british_afrca_mac_body");
	addMetalHat("character_british_afrca_mac_radio");
	addMetalHat("character_british_afrca_mcgregor_low");
	addMetalHat("character_british_afrca_shortsleeve_body");
	addMetalHat("character_british_normandy_a");
	addMetalHat("character_british_normandy_b");
	addMetalHat("character_british_normandy_c");
	addMetalHat("character_british_normandy_mac_body");
	addMetalHat("character_german_afrca_body");
	addMetalHat("character_german_afrca_casualbody");
	addMetalHat("character_german_camo_fat");
	addMetalHat("character_german_normandy_coat_dark");
	addMetalHat("character_german_normandy_fat");
	addMetalHat("character_german_normandy_fat_injured");
	addMetalHat("character_german_normandy_officer");
	addMetalHat("character_german_normandy_thin");
	addMetalHat("character_german_normandy_thin_injured");
	addMetalHat("character_german_winter_light");
	addMetalHat("character_german_winter_masked_dark");
	addMetalHat("character_german_winter_mg42_low");
	addMetalHat("character_russian_padded_b");
	addMetalHat("character_russian_trench_b");
	
	anim.fatGuy = []; // fat models
	addFatGuy("character_german_camo_fat");
	addFatGuy("character_german_normandy_fat");
	addFatGuy("character_russian_trench_a");
	addFatGuy("character_german_normandy_fat_injured");
}	

addNoHat(model)
{
	anim.noHat[model] = 1;
}

addNoHatClassname(model)
{
	anim.noHatClassname[model] = 1;
}

addMetalHat(model)
{
	anim.metalHat[model] = 1;
}

addFatGuy(model)
{
	anim.fatGuy[model] = 1;
}

initWindowTraverse()
{
	// used to blend the traverse window_down smoothly at the end
	level.window_down_height[0] = -36.8552;
	level.window_down_height[1] = -27.0095;
	level.window_down_height[2] = -15.5981;
	level.window_down_height[3] = -4.37769;
	level.window_down_height[4] = 17.7776;
	level.window_down_height[5] = 59.8499;
	level.window_down_height[6] = 104.808;
	level.window_down_height[7] = 152.325;
	level.window_down_height[8] = 201.052;
	level.window_down_height[9] = 250.244;
	level.window_down_height[10] = 298.971;
	level.window_down_height[11] = 330.681;
}

initMoveStartStopTransitions()
{
	transTypes = [];
	transTypes[0] = "left";
	transTypes[1] = "right";
	transTypes[2] = "left_crouch";
	transTypes[3] = "right_crouch";
	transTypes[4] = "crouch";
	transTypes[5] = "stand";
	transTypes[6] = "exposed";
	transTypes[7] = "exposed_crouch";
	transTypes[8] = "stand_saw";
	transTypes[9] = "crouch_saw";

	anim.approach_types = [];
	standing = 0;
	crouching = 1;
	
	anim.approach_types[ "Cover Left" ] = [];
	anim.approach_types[ "Cover Left" ][ standing ] = "left";
	anim.approach_types[ "Cover Left" ][ crouching ] = "left_crouch";
	anim.approach_types[ "Cover Left Wide" ] = anim.approach_types[ "Cover Left" ];
	
	anim.approach_types[ "Cover Right" ] = [];
	anim.approach_types[ "Cover Right" ][ standing ] = "right";
	anim.approach_types[ "Cover Right" ][ crouching ] = "right_crouch";
	anim.approach_types[ "Cover Right Wide" ] = anim.approach_types[ "Cover Right" ];
	
	anim.approach_types[ "Cover Crouch" ] = [];
	anim.approach_types[ "Cover Crouch" ][ standing ] = "crouch";
	anim.approach_types[ "Cover Crouch" ][ crouching ] = "crouch";
	anim.approach_types[ "Conceal Crouch" ] = anim.approach_types[ "Cover Crouch" ];
	anim.approach_types[ "Cover Crouch Window" ] = anim.approach_types[ "Cover Crouch" ];
	
	anim.approach_types[ "Cover Stand" ] = [];
	anim.approach_types[ "Cover Stand" ][ standing ] = "stand";
	anim.approach_types[ "Cover Stand" ][ crouching ] = "stand";
	anim.approach_types[ "Conceal Stand" ] = anim.approach_types[ "Cover Stand" ];
	
	anim.approach_types[ "Path" ] = [];
	anim.approach_types[ "Path" ][ standing ] = "exposed";
	anim.approach_types[ "Path" ][ crouching ] = "exposed_crouch";
	anim.approach_types[ "Guard"] = anim.approach_types[ "Path" ];
	anim.approach_types[ "Turret"] = anim.approach_types[ "Path" ];

	// CORNER TRANSITIONS ANIMS
	anim.coverTrans = [];
	anim.coverExit = [];
	
	anim.traverseInfo = [];
	// indicies indicate the keyboard numpad directions (8 is forward)
	// 7  8  9
	// 4     6	 <- 5 is invalid
	// 1  2  3

	/*************************************************
	*    Entrance Animations
	*************************************************/
	
	anim.coverTrans["right"       ][1] = %corner_standR_trans_IN_1;
	anim.coverTrans["right"       ][2] = %corner_standR_trans_IN_2;
	anim.coverTrans["right"       ][3] = %corner_standR_trans_IN_3;
	anim.coverTrans["right"       ][4] = %corner_standR_trans_IN_4;
	anim.coverTrans["right"       ][6] = %corner_standR_trans_IN_6;
	//im.coverTrans["right"       ][7] = can't approach from this direction;
	anim.coverTrans["right"       ][8] = %corner_standR_trans_IN_8;
	anim.coverTrans["right"       ][9] = %corner_standR_trans_IN_9;

	anim.coverTrans["right_crouch"][1] = %CornerCrR_trans_IN_ML;
	anim.coverTrans["right_crouch"][2] = %CornerCrR_trans_IN_M;
	anim.coverTrans["right_crouch"][3] = %CornerCrR_trans_IN_MR;
	anim.coverTrans["right_crouch"][4] = %CornerCrR_trans_IN_L;
	anim.coverTrans["right_crouch"][6] = %CornerCrR_trans_IN_R;
	//im.coverTrans["right_crouch"][7] = can't approach from this direction;
	anim.coverTrans["right_crouch"][8] = %CornerCrR_trans_IN_F;
	anim.coverTrans["right_crouch"][9] = %CornerCrR_trans_IN_MF;

	anim.coverTrans["left"        ][1] = %corner_standL_trans_IN_1;
	anim.coverTrans["left"        ][2] = %corner_standL_trans_IN_2;
	anim.coverTrans["left"        ][3] = %corner_standL_trans_IN_3;
	anim.coverTrans["left"        ][4] = %corner_standL_trans_IN_4;
	anim.coverTrans["left"        ][6] = %corner_standL_trans_IN_6;
	anim.coverTrans["left"        ][7] = %corner_standL_trans_IN_7;
	anim.coverTrans["left"        ][8] = %corner_standL_trans_IN_8;
	//im.coverTrans["left"        ][9] = can't approach from this direction;
	
	anim.coverTrans["left_crouch" ][1] = %CornerCrL_trans_IN_ML;
	anim.coverTrans["left_crouch" ][2] = %CornerCrL_trans_IN_M;
	anim.coverTrans["left_crouch" ][3] = %CornerCrL_trans_IN_MR;
	anim.coverTrans["left_crouch" ][4] = %CornerCrL_trans_IN_L;
	anim.coverTrans["left_crouch" ][6] = %CornerCrL_trans_IN_R;
	anim.coverTrans["left_crouch" ][7] = %CornerCrL_trans_IN_MF;
	anim.coverTrans["left_crouch" ][8] = %CornerCrL_trans_IN_F;
	//im.coverTrans["left_crouch" ][9] = can't approach from this direction;
	
	anim.coverTrans["crouch"      ][1] = %covercrouch_run_in_ML;
	anim.coverTrans["crouch"      ][2] = %covercrouch_run_in_M;
	anim.coverTrans["crouch"      ][3] = %covercrouch_run_in_MR;
	anim.coverTrans["crouch"      ][4] = %covercrouch_run_in_L;
	anim.coverTrans["crouch"      ][6] = %covercrouch_run_in_R;
	//im.coverTrans["crouch"      ][7] = can't approach from this direction;
	//im.coverTrans["crouch"      ][8] = can't approach from this direction;
	//im.coverTrans["crouch"      ][9] = can't approach from this direction;
	
	anim.coverTrans["stand"       ][1] = %coverstand_trans_IN_ML;
	anim.coverTrans["stand"       ][2] = %coverstand_trans_IN_M;
	anim.coverTrans["stand"       ][3] = %coverstand_trans_IN_MR;
	anim.coverTrans["stand"       ][4] = %coverstand_trans_IN_L;
	anim.coverTrans["stand"       ][6] = %coverstand_trans_IN_R;
	//im.coverTrans["stand"       ][7] = can't approach from this direction;
	//im.coverTrans["stand"       ][8] = can't approach from this direction;
	//im.coverTrans["stand"       ][9] = can't approach from this direction;

	anim.coverTrans["stand_saw"   ][1] = %saw_gunner_runin_ML;
	anim.coverTrans["stand_saw"   ][2] = %saw_gunner_runin_M;
	anim.coverTrans["stand_saw"   ][3] = %saw_gunner_runin_MR;
	anim.coverTrans["stand_saw"   ][4] = %saw_gunner_runin_L;
	anim.coverTrans["stand_saw"   ][6] = %saw_gunner_runin_R;

	anim.coverTrans["crouch_saw"   ][1] = %saw_gunner_lowwall_runin_ML;
	anim.coverTrans["crouch_saw"   ][2] = %saw_gunner_lowwall_runin_M;
	anim.coverTrans["crouch_saw"   ][3] = %saw_gunner_lowwall_runin_MR;
	anim.coverTrans["crouch_saw"   ][4] = %saw_gunner_lowwall_runin_L;
	anim.coverTrans["crouch_saw"   ][6] = %saw_gunner_lowwall_runin_R;
	
	// we need 45 degree angle approaches for exposed...
	anim.coverTrans["exposed"     ] = []; // need this or it chokes on the next line due to assigning undefined...
	anim.coverTrans["exposed"     ][1] = undefined;
	anim.coverTrans["exposed"     ][2] = %run_2_stand_F_6;
	anim.coverTrans["exposed"     ][3] = undefined;
	anim.coverTrans["exposed"     ][4] = %run_2_stand_90L;
	anim.coverTrans["exposed"     ][6] = %run_2_stand_90R;
	anim.coverTrans["exposed"     ][7] = undefined;
	anim.coverTrans["exposed"     ][8] = %run_2_stand_180L;
	anim.coverTrans["exposed"     ][9] = undefined;

	anim.coverTrans["exposed_crouch"] = []; // need this or it chokes on the next line due to assigning undefined...
	anim.coverTrans["exposed_crouch"][1] = undefined;
	anim.coverTrans["exposed_crouch"][2] = %run_2_crouch_F;
	anim.coverTrans["exposed_crouch"][3] = undefined;
	anim.coverTrans["exposed_crouch"][4] = %run_2_crouch_90L;
	anim.coverTrans["exposed_crouch"][6] = %run_2_crouch_90R;
	anim.coverTrans["exposed_crouch"][7] = undefined;
	anim.coverTrans["exposed_crouch"][8] = %run_2_crouch_180L;
	anim.coverTrans["exposed_crouch"][9] = undefined;	
	
	
	/*************************************************
	*    Exit Animations
	*************************************************/

	anim.coverExit["right"       ][1] = %corner_standR_trans_OUT_1;
	anim.coverExit["right"       ][2] = %corner_standR_trans_OUT_2;
	anim.coverExit["right"       ][3] = %corner_standR_trans_OUT_3;
	anim.coverExit["right"       ][4] = %corner_standR_trans_OUT_4;
	anim.coverExit["right"       ][6] = %corner_standR_trans_OUT_6;
	//im.coverExit["right"       ][7] = can't approach from this direction;
	anim.coverExit["right"       ][8] = %corner_standR_trans_OUT_8;
	anim.coverExit["right"       ][9] = %corner_standR_trans_OUT_9;
	
	anim.coverExit["right_crouch"][1] = %CornerCrR_trans_OUT_ML;
	anim.coverExit["right_crouch"][2] = %CornerCrR_trans_OUT_M;
	anim.coverExit["right_crouch"][3] = %CornerCrR_trans_OUT_MR;
	anim.coverExit["right_crouch"][4] = %CornerCrR_trans_OUT_L;
	anim.coverExit["right_crouch"][6] = %CornerCrR_trans_OUT_R;
	//im.coverExit["right_crouch"][7] = can't approach from this direction;
	anim.coverExit["right_crouch"][8] = %CornerCrR_trans_OUT_F;
	anim.coverExit["right_crouch"][9] = %CornerCrR_trans_OUT_MF;
	
	anim.coverExit["left"        ][1] = %corner_standL_trans_OUT_1;
	anim.coverExit["left"        ][2] = %corner_standL_trans_OUT_2;
	anim.coverExit["left"        ][3] = %corner_standL_trans_OUT_3;
	anim.coverExit["left"        ][4] = %corner_standL_trans_OUT_4;
	anim.coverExit["left"        ][6] = %corner_standL_trans_OUT_6;
	anim.coverExit["left"        ][7] = %corner_standL_trans_OUT_7;
	anim.coverExit["left"        ][8] = %corner_standL_trans_OUT_8;
	//im.coverExit["left"        ][9] = can't approach from this direction;
	
	anim.coverExit["left_crouch" ][1] = %CornerCrL_trans_OUT_ML;
	anim.coverExit["left_crouch" ][2] = %CornerCrL_trans_OUT_M;
	anim.coverExit["left_crouch" ][3] = %CornerCrL_trans_OUT_MR;
	anim.coverExit["left_crouch" ][4] = %CornerCrL_trans_OUT_L;
	anim.coverExit["left_crouch" ][6] = %CornerCrL_trans_OUT_R;
	anim.coverExit["left_crouch" ][7] = %CornerCrL_trans_OUT_MF;
	anim.coverExit["left_crouch" ][8] = %CornerCrL_trans_OUT_F;
	//im.coverExit["left_crouch" ][9] = can't approach from this direction;
	
	anim.coverExit["crouch"      ][1] = %covercrouch_run_out_ML;
	anim.coverExit["crouch"      ][2] = %covercrouch_run_out_M;
	anim.coverExit["crouch"      ][3] = %covercrouch_run_out_MR;
	anim.coverExit["crouch"      ][4] = %covercrouch_run_out_L;
	anim.coverExit["crouch"      ][6] = %covercrouch_run_out_R;
	//im.coverExit["crouch"      ][7] = can't approach from this direction;
	//im.coverExit["crouch"      ][8] = can't approach from this direction;
	//im.coverExit["crouch"      ][9] = can't approach from this direction;
	
	anim.coverExit["stand"       ][1] = %coverstand_trans_OUT_ML;
	anim.coverExit["stand"       ][2] = %coverstand_trans_OUT_M;
	anim.coverExit["stand"       ][3] = %coverstand_trans_OUT_MR;
	anim.coverExit["stand"       ][4] = %coverstand_trans_OUT_L;
	anim.coverExit["stand"       ][6] = %coverstand_trans_OUT_R;
	//im.coverExit["stand"       ][7] = can't approach from this direction;
	//im.coverExit["stand"       ][8] = can't approach from this direction;
	//im.coverExit["stand"       ][9] = can't approach from this direction;
	anim.coverExit["stand_saw"   ][1] = %saw_gunner_runout_ML;
	anim.coverExit["stand_saw"   ][2] = %saw_gunner_runout_M;
	anim.coverExit["stand_saw"   ][3] = %saw_gunner_runout_MR;
	anim.coverExit["stand_saw"   ][4] = %saw_gunner_runout_L;
	anim.coverExit["stand_saw"   ][6] = %saw_gunner_runout_R;
	
	anim.coverExit["crouch_saw"	 ][1] = %saw_gunner_lowwall_runout_ML;
	anim.coverExit["crouch_saw"	 ][2] = %saw_gunner_lowwall_runout_M;
	anim.coverExit["crouch_saw"	 ][3] = %saw_gunner_lowwall_runout_MR;
	anim.coverExit["crouch_saw"	 ][4] = %saw_gunner_lowwall_runout_L;
	anim.coverExit["crouch_saw"	 ][6] = %saw_gunner_lowwall_runout_R;

	// we need 45 degree angle exits for exposed...
	anim.coverExit["exposed"     ] = []; // need this or it chokes on the next line due to assigning undefined...
	anim.coverExit["exposed"     ][1] = undefined;
	anim.coverExit["exposed"     ][2] = %stand_2_run_180_med; // there is also _short, doesn't look as good
	anim.coverExit["exposed"     ][3] = undefined;
	anim.coverExit["exposed"     ][4] = %stand_2_run_L;
	anim.coverExit["exposed"     ][6] = %stand_2_run_R;
	anim.coverExit["exposed"     ][7] = undefined;
	anim.coverExit["exposed"     ][8] = %stand_2_run_F_2;
	anim.coverExit["exposed"     ][9] = undefined;

	anim.coverExit["exposed_crouch"] = []; // need this or it chokes on the next line due to assigning undefined...
	anim.coverExit["exposed_crouch"][1] = undefined;
	anim.coverExit["exposed_crouch"][2] = %crouch_2run_180;
	anim.coverExit["exposed_crouch"][3] = undefined;
	anim.coverExit["exposed_crouch"][4] = %crouch_2run_L;
	anim.coverExit["exposed_crouch"][6] = %crouch_2run_R;
	anim.coverExit["exposed_crouch"][7] = undefined;
	anim.coverExit["exposed_crouch"][8] = %crouch_2run_F;
	anim.coverExit["exposed_crouch"][9] = undefined;
	
	anim.coverTransDist = [];
	anim.coverExitDist = [];
	
	// this is the distance moved to get around corner for 7, 8, 9 directions
	anim.coverExitPostDist = [];

	// this is the distance moved to get around corner for 7, 8, 9 directions
	anim.coverTransPreDist = [];
	
	anim.coverTransAngles = [];
	anim.coverExitAngles = [];

	for ( i = 1; i <= 6; i++ )
	{
		if ( i == 5 )
		{
			continue;
		}
		
		for ( j = 0; j < transTypes.size; j++ )
		{
			trans = transTypes[j];
			
			if ( IsDefined( anim.coverTrans[ trans ][i] ) )
			{
				anim.coverTransDist  [ trans ][i] = getMoveDelta ( anim.coverTrans[ trans ][i], 0, 1 );
				anim.coverTransAngles[ trans ][i] = getAngleDelta( anim.coverTrans[ trans ][i], 0, 1 );
			}
			
			if ( IsDefined( anim.coverExit [ trans ] ) && IsDefined( anim.coverExit [ trans ][i] ) )
			{
				anim.coverExitDist   [ trans ][i] = getMoveDelta ( anim.coverExit [ trans ][i], 0, 1 );
				anim.coverExitAngles [ trans ][i] = getAngleDelta( anim.coverExit [ trans ][i], 0, 1 );
			}
		}
	}
	
	exposedTransTypes = [];
	exposedTransTypes[0] = "exposed";
	exposedTransTypes[1] = "exposed_crouch";
	
	anim.longestExposedApproachDist = 0;

	for ( j = 0; j < exposedTransTypes.size; j++ )
	{
		trans = exposedTransTypes[j];
		for ( i = 7; i <= 9; i++ )
		{
			if ( IsDefined( anim.coverTrans[ trans ][i] ) )
			{
				anim.coverTransDist  [ trans ][i] = getMoveDelta ( anim.coverTrans[ trans ][i], 0, 1 );
				anim.coverTransAngles[ trans ][i] = getAngleDelta( anim.coverTrans[ trans ][i], 0, 1 );
			}
			
			if ( IsDefined( anim.coverExit [ trans ][i] ) )
			{
				anim.coverExitDist   [ trans ][i] = getMoveDelta ( anim.coverExit [ trans ][i], 0, 1 );
				anim.coverExitAngles [ trans ][i] = getAngleDelta( anim.coverExit [ trans ][i], 0, 1 );
			}
		}
		
		for ( i = 1; i <= 9; i++ )
		{
			if ( !IsDefined( anim.coverTrans[trans][i] ) )
			{
				continue;
			}
			
			len = length( anim.coverTransDist[trans][i] );
			if ( len > anim.longestExposedApproachDist )
			{
				anim.longestExposedApproachDist = len;
			}
		}
	}
	

	// the FindBestSplitTime calls below are used to find these values.
	// all of this is for corner nodes.
	anim.coverExitSplit = [];
	anim.coverTransSplit = [];
	
	anim.coverTransSplit["left"][7] = 0.369369; // delta of (35.5356, 3.27114, 0)
	anim.coverTransSplit["left_crouch"][7] = 0.277277; // delta of (38.5093, 6.37286, 0)
	anim.coverExitSplit["left"][7] = 0.646647; // delta of (36.3768, 4.37581, 0)
	anim.coverExitSplit["left_crouch"][7] = 0.764765; // delta of (36.7695, 4.82297, 0)
	anim.coverTransSplit["left"][8] = 0.463463; // delta of (32.9564, 0.950555, 0)
	anim.coverTransSplit["left_crouch"][8] = 0.339339; // delta of (35.0497, 3.12251, 0)
	anim.coverExitSplit["left"][8] = 0.677678; // delta of (34.3012, 2.25822, 0)
	anim.coverExitSplit["left_crouch"][8] = 0.58959; // delta of (36.3154, 4.34119, 0)
	anim.coverTransSplit["right"][8] = 0.458458; // delta of (35.6571, 3.63511, 0)
	anim.coverTransSplit["right_crouch"][8] = 0.329329; // delta of (36.398, 4.45949, 0)
	anim.coverExitSplit["right"][8] = 0.457457; // delta of (36.3085, 4.34586, 0)
	anim.coverExitSplit["right_crouch"][8] = 0.636637; // delta of (40.441, 8.59943, -0.0001)
	anim.coverTransSplit["right"][9] = 0.546547; // delta of (37.7732, 5.76641, 0)
	anim.coverTransSplit["right_crouch"][9] = 0.349349; // delta of (36.0788, 3.95538, 0)
	anim.coverExitSplit["right"][9] = 0.521522; // delta of (35.3195, 3.24431, 0)
	anim.coverExitSplit["right_crouch"][9] = 0.664665; // delta of (33.4424, 1.40398, -0.0001)
	
	for ( i = 7; i <= 8; i++ )
	{
		anim.coverTransPreDist["left"        ][i] = getMoveDelta ( anim.coverTrans["left"        ][i], 0, getTransSplitTime( "left", i ) );
		anim.coverTransDist   ["left"        ][i] = getMoveDelta ( anim.coverTrans["left"        ][i], 0, 1 ) - anim.coverTransPreDist["left"][i];
		anim.coverTransAngles ["left"        ][i] = getAngleDelta( anim.coverTrans["left"        ][i], 0, 1 );
		anim.coverTransPreDist["left_crouch" ][i] = getMoveDelta ( anim.coverTrans["left_crouch" ][i], 0, getTransSplitTime( "left_crouch", i ) );
		anim.coverTransDist   ["left_crouch" ][i] = getMoveDelta ( anim.coverTrans["left_crouch" ][i], 0, 1 ) - anim.coverTransPreDist["left_crouch"][i];
		anim.coverTransAngles ["left_crouch" ][i] = getAngleDelta( anim.coverTrans["left_crouch" ][i], 0, 1 );

		anim.coverExitDist    ["left"        ][i] = getMoveDelta ( anim.coverExit ["left"        ][i], 0, getExitSplitTime( "left", i ) );
		anim.coverExitPostDist["left"        ][i] = getMoveDelta ( anim.coverExit ["left"        ][i], 0, 1 ) - anim.coverExitDist["left"][i];
		anim.coverExitAngles  ["left"        ][i] = getAngleDelta( anim.coverExit ["left"        ][i], 0, 1 );
		anim.coverExitDist    ["left_crouch" ][i] = getMoveDelta ( anim.coverExit ["left_crouch" ][i], 0, getExitSplitTime( "left_crouch", i ) );
		anim.coverExitPostDist["left_crouch" ][i] = getMoveDelta ( anim.coverExit ["left_crouch" ][i], 0, 1 ) - anim.coverExitDist["left_crouch"][i];
		anim.coverExitAngles  ["left_crouch" ][i] = getAngleDelta( anim.coverExit ["left"        ][i], 0, 1 );
	}

	for ( i = 8; i <= 9; i++ )
	{
		anim.coverTransPreDist["right"       ][i] = getMoveDelta ( anim.coverTrans["right"       ][i], 0, getTransSplitTime( "right", i ) );
		anim.coverTransDist   ["right"       ][i] = getMoveDelta ( anim.coverTrans["right"       ][i], 0, 1 ) - anim.coverTransPreDist["right"][i];
		anim.coverTransAngles ["right"       ][i] = getAngleDelta( anim.coverTrans["right"       ][i], 0, 1 );
		anim.coverTransPreDist["right_crouch"][i] = getMoveDelta ( anim.coverTrans["right_crouch"][i], 0, getTransSplitTime( "right_crouch", i ) );
		anim.coverTransDist   ["right_crouch"][i] = getMoveDelta ( anim.coverTrans["right_crouch"][i], 0, 1 ) - anim.coverTransPreDist["right_crouch"][i];
		anim.coverTransAngles ["right_crouch"][i] = getAngleDelta( anim.coverTrans["right_crouch"][i], 0, 1 );

		anim.coverExitDist    ["right"       ][i] = getMoveDelta ( anim.coverExit ["right"       ][i], 0, getExitSplitTime( "right", i ) );
		anim.coverExitPostDist["right"       ][i] = getMoveDelta ( anim.coverExit ["right"       ][i], 0, 1 ) - anim.coverExitDist["right"][i];
		anim.coverExitAngles  ["right"       ][i] = getAngleDelta( anim.coverExit ["right"       ][i], 0, 1 );
		anim.coverExitDist    ["right_crouch"][i] = getMoveDelta ( anim.coverExit ["right_crouch"][i], 0, getExitSplitTime( "right_crouch", i ) );
		anim.coverExitPostDist["right_crouch"][i] = getMoveDelta ( anim.coverExit ["right_crouch"][i], 0, 1 ) - anim.coverExitDist["right_crouch"][i];
		anim.coverExitAngles  ["right_crouch"][i] = getAngleDelta( anim.coverExit ["right_crouch"][i], 0, 1 );
	}

	// ShortCircuiting Prototype - Store the notetrack times and distances once
	anim.coverNotetrackExitInfo = [];	
	anim.coverNotetrackArrivalInfo = [];

	for( i = 1; i <= 9; i++ )
	{
		for( j = 0; j < transTypes.size - 1; j++ ) // we dont want wall_over_40 currently.
		{
			trans = transTypes[j];
			
			if( IsDefined( anim.coverTrans[ trans ] ) && IsDefined( anim.coverTrans[ trans ][i] ) )
			{
				// get all the notetracks stored in an array, this functionality is only for developer
				notetracks = getnotetracksindelta( anim.coverTrans[ trans ][i], 0, 9999 );

				if(notetracks.size > 0)
				{
					anim.coverNotetrackArrivalInfo[ trans + "_" + i ] = [];
					anim.coverNotetrackArrivalInfo[ trans + "_" + i ] = notetracks;
				}

			}

			if( IsDefined( anim.coverExit[ trans ] ) && IsDefined( anim.coverExit[ trans ][i] ) )
			{
				// get all the notetracks stored in an array, this functionality is only for developer
				notetracks = getnotetracksindelta( anim.coverExit[ trans ][i], 0, 9999 );
	
				if(notetracks.size > 0)
				{
					anim.coverNotetrackExitInfo[ trans + "_" + i ] = [];
					anim.coverNotetrackExitInfo[ trans + "_" + i ] = notetracks;
				}

			}
	
		}
	}
}

getExitSplitTime( approachType, dir )
{
	return anim.coverExitSplit[ approachType ][ dir ];
}

getTransSplitTime( approachType, dir )
{
	return anim.coverTransSplit[ approachType ][ dir ];
}

firstInit()
{
	/#
	debug_replay("File: init.gsc. Function: firstInit()\n");
	#/
	
	// Initialization that should happen once per level
	if ( IsDefined (anim.NotFirstTime) ) // Use this to trigger the first init
	{
		/#
		debug_replay("File: init.gsc. Function: firstInit() - COMPLETE EARLY\n");
		#/
		return;
	}
	
	anim.NotFirstTime = true;
	
	anim.useFacialAnims = false; // remove me when facial anims are fixed

	if ( !IsDefined( anim.dog_health ) )
	{
		anim.dog_health = 1;
	}
		
	if ( !IsDefined( anim.dog_presstime ) )
	{
		anim.dog_presstime = 350;
	}
		
	if ( !IsDefined( anim.dog_hits_before_kill ) )
	{
		anim.dog_hits_before_kill = 1;
	}

	level.nextGrenadeDrop = RandomInt(3);
	level.lastPlayerSighted = 100;
	anim.defaultException = animscripts\zombie_init::empty;
	
	/#
	if (GetDebugDvar("debug_noanimscripts") == "")
	{
		SetDvar("debug_noanimscripts", "off");
	}
	else if (GetDebugDvar("debug_noanimscripts") == "on")
	{
		anim.defaultException = animscripts\zombie_init::infiniteLoop;
	}

	if (GetDebugDvar("debug_grenadehand") == "")
	{
		SetDvar("debug_grenadehand", "off");
	}
		
	if (GetDebugDvar("anim_trace") == "")
	{
		SetDvar("anim_trace", "-1");
	}

	if (GetDebugDvar("anim_dotshow") == "")
	{
		SetDvar("anim_dotshow", "-1");
	}

	if (GetDebugDvar("anim_debug") == "")
	{
		SetDvar("anim_debug", "");
	}

	if (GetDebugDvar("debug_misstime") == "")
	{
		SetDvar("debug_misstime", "");
	}

	if (GetDvar( #"modern") == "")
	{
		SetDvar("modern", "on");
	}
	#/
	
	anim.sniperRifles = [];
	anim.sniperRifles["aw50"] = 1;
	anim.sniperRifles["dragunov"] = 1;
	anim.sniperRifles["m14_scoped"] = 1;
	anim.sniperRifles["m14_scoped_ghil"] = 1;
	anim.sniperRifles["m14_scoped_silencer"] = 1;
	anim.sniperRifles["m14_scoped_silencer_woodland"] = 1;
	anim.sniperRifles["m14_scoped_woodland"] = 1;
	anim.sniperRifles["m40a3"] = 1;
	anim.sniperRifles["remington700"] = 1;
	anim.sniperRifles["barrett"] = 1;
		
	SetDvar( "scr_expDeathMayMoveCheck", "on" );
	
	maps\_names::setup_names();

	// Global constants
  anim.lastSideStepAnim = 0;
  anim.meleeRange = 64;
	anim.meleeRangeSq = anim.meleeRange * anim.meleeRange;
	anim.standRangeSq = 512*512;
	anim.chargeRangeSq = 200*200;
	anim.chargeLongRangeSq = 512*512;
	anim.aiVsAiMeleeRangeSq = 400*400;
	
	anim.animFlagNameIndex = 0;
	
	if (!IsDefined (level.squadEnt))
	{
		level.squadEnt = [];
	}

	anim.masterGroup["axis"] = SpawnStruct();
	anim.masterGroup["axis"].sightTime = 0;
	anim.masterGroup["allies"] = SpawnStruct();
	anim.masterGroup["allies"].sightTime = 0;
	anim.scriptSquadGroup = [];

	initMoveStartStopTransitions();

	thread setupHats();
	
	anim.lastUpwardsDeathTime = 0;
	anim.backpedalRangeSq = 60*60;
	anim.dodgeRangeSq = 300*300;			// Guys only dodge when inside this range.
	anim.blindAccuracyMult["allies"] = 0.5;
	anim.blindAccuracyMult["axis"] = 0.1;
	anim.ramboAccuracyMult = 1.0;
	anim.runAccuracyMult = 0.5;
	anim.combatMemoryTimeConst = 10000;
	anim.combatMemoryTimeRand = 6000;
	anim.scriptChange = "script_change";
	
	anim.grenadeTimers["player_fraggrenade"] = randomIntRange( 1000, 20000 );
	anim.grenadeTimers["player_flash_grenade"] = randomIntRange( 1000, 20000 );
	anim.grenadeTimers["player_double_grenade"] = randomIntRange( 10000, 60000 );
	anim.grenadeTimers["AI_fraggrenade"] = randomIntRange( 0, 20000 );
	anim.grenadeTimers["AI_flash_grenade"] = randomIntRange( 0, 20000 );

	anim.numGrenadesInProgressTowardsPlayer = 0;
	anim.lastGrenadeLandedNearPlayerTime = -1000000;
	anim.lastFragGrenadeToPlayerStart    = -1000000;
	thread setNextPlayerGrenadeTime();

	/#
	thread animscripts\combat_utility::grenadeTimerDebug();
	#/
		
	// MikeD (10/23/2007 10:38:58): Gib Support
	anim.lastGibTime 	= 0;
	anim.gibDelay 		= 3 * 1000; // 3 seconds
	anim.minGibs		= 2;
	anim.maxGibs		= 4;
	anim.totalGibs		= RandomIntRange( anim.minGibs, anim.maxGibs );
	
	setEnv("none");

	anim.corner_straight_yaw_limit = 36;

	if (!IsDefined(anim.optionalStepEffectFunction))
	{
		anim.optionalStepEffects = [];
		anim.optionalStepEffectFunction = ::empty;
	}

	// string based array for notetracks
	anim.notetracks = [];
	animscripts\zombie_shared::registerNoteTracks();
	
	/#
	if (GetDvar( #"debug_delta") == "")
	{
		SetDvar("debug_delta", "off");
	}
	#/

	if ( !IsDefined( level.flag ) )
	{
		level.flag = [];
		level.flags_lock = [];
	}

	maps\_gameskill::setSkill(undefined,1);
	level.painAI = undefined;
	
	animscripts\zombie_SetPoseMovement::InitPoseMovementFunctions();
	animscripts\face::InitLevelFace();
	
	anim.set_a_b[0] = "a";
	anim.set_a_b[1] = "b";

	anim.set_a_b_c[0] = "a";
	anim.set_a_b_c[1] = "b";
	anim.set_a_b_c[2] = "c";

	anim.set_a_c[0] = "a";
	anim.set_a_c[1] = "c";
	
	anim.num_to_letter[1] = "a";
	anim.num_to_letter[2] = "b";
	anim.num_to_letter[3] = "c";
	anim.num_to_letter[4] = "d";
	anim.num_to_letter[5] = "e";
	anim.num_to_letter[6] = "f";
	anim.num_to_letter[7] = "g";
	anim.num_to_letter[8] = "h";
	anim.num_to_letter[9] = "i";
	anim.num_to_letter[10] = "j";

	anim.maymoveCheckEnabled = true; // corner_axis doesnt do the check if this is false, for credits

	anim.badPlaces = []; // queue for animscript badplaces
	anim.badPlaceInt = 0; // assigns unique names to animscript badplaces since we cant save a badplace as an entity

	animscripts\squadmanager::init_squadManager();

	//animscripts\battleChatter::init_battleChatter();

	anim thread animscripts\battleChatter::bcsDebugWaiter();
	anim.reacquireNum = 0;
	initWindowTraverse();
	
	anim.coverCrouchLeanPitch = -55;
	
	anim.lastCarExplosionTime = -100000;

	setupRandomTable();
	
	/#
	debug_replay("File: init.gsc. Function: firstInit() - COMPLETE\n");
	#/
}

onPlayerConnect()
{
	player = self;
	
	// make sure the init has been called
	firstInit();

	player.invul = false;
	
	println("*************************************init::onPlayerConnect");
	player thread animscripts\battlechatter::player_init();
	player thread animscripts\combat_utility::player_init();

	player thread maps\_serverfaceanim::init_serverfaceanim();

	player thread animscripts\combat_utility::watchReloading();
	player thread animscripts\squadManager::addPlayerToSquad();
	player thread animscripts\battleChatter_ai::addToSystem();
}

setNextPlayerGrenadeTime()
{
	waittillframeend;
	// might not be defined if maps\_load::main() wasn't called
	if ( IsDefined( anim.playerGrenadeRangeTime ) )
	{
		maxTime = int( anim.playerGrenadeRangeTime * 0.7 );
		if ( maxTime < 1 )
		{
			maxTime = 1;
		}

		anim.grenadeTimers["player_fraggrenade"] = randomIntRange( 0, maxTime );
		anim.grenadeTimers["player_flash_grenade"] = randomIntRange( 0, maxTime );
	}
	
	if ( IsDefined( anim.playerDoubleGrenadeTime ) )
	{
		maxTime = int( anim.playerDoubleGrenadeTime );
		minTime = int( maxTime / 2 );
		if ( maxTime <= minTime )
		{
			maxTime = minTime + 1;
		}

		anim.grenadeTimers["player_double_grenade"] = randomIntRange( minTime, maxTime );
	}
}

beginGrenadeTracking()
{
	self endon ( "death" );
	
	for ( ;; )
	{
		self waittill ( "grenade_fire", grenade, weaponName );
		grenade thread grenade_earthQuake();
	}
}

setupRandomTable()
{
	// 60 is chosen because it is divisible by 1,2,3,4,5, and 6,
	// and it's also high enough to get some good randomness over different seed values
	anim.randomIntTableSize = 60;

	anim.randomIntTable = [];
	for ( i = 0; i < anim.randomIntTableSize; i++ )
	{
		anim.randomIntTable[i] = i;
	}
	
	for ( i = 0; i < anim.randomIntTableSize; i++ )
	{
		switchwith = RandomInt( anim.randomIntTableSize );
		temp = anim.randomIntTable[i];
		anim.randomIntTable[i] = anim.randomIntTable[switchwith];
		anim.randomIntTable[switchwith] = temp;
	}
}

endOnDeath()
{
	self waittill( "death" );
	waittillframeend;
	self notify ( "end_explode" );
}

grenade_earthQuake()
{
	self thread endOnDeath();
	self endon( "end_explode" );
	self waittill( "explode", position );
	PlayRumbleOnPosition( "grenade_rumble", position );
	earthquake( 0.3, 0.5, position, 400 );
}

onDeath()
{
	self waittill("death");
	if ( !IsDefined( self ) )
	{
		// we were deleted and we're not running the death script.
		// still safe to access our variables as a removed entity though:
		if ( IsDefined( self.a.usingTurret ) )
		{
			self.a.usingTurret delete();
		}
	}
}