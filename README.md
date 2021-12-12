# Formula
More than just a [Calculator.](https://forums.alliedmods.net/showthread.php?p=1271449)

Sometimes you just want a quick and simple solution. Maybe you'd wish that one ConVar had a dynamic 
value based on e.g. player count? Or how about executing commands based on some value?

This plugin can do that for you. Keep in mind that a custom plugin will always be more performant, but for quick, simple solutions that you can tweak with relative ease, it should be just fine.

## Formulas

The parser for formulas supports plus, minus, negative signum, multiplication, division and modulo as well as grouping, variables and some functions. Grouping can be done with round or square brackets interchangeably, but round brackets might not work from chat in games where valve broke double quotes.

Variables can be ConVar (just use the ConVar name), user variables (names start with $) or target selectors (`@all` for example). For target selectors it will use the number of matches.

The following function are currently supported:

| Name | Desc |
|-----|-----|
| min(a,b) | The smaller of two values |
| max(a,b) | The larget of two values |
| clamp(low,v,high) | Short for max(low,min(v,high)) |
| abs(a) | The absolute (positive) value |
| round(a) | Round the value to the next integer |
| ceil(a) | Round the value up |
| floor(a) | Round the value down |
| lerp(a,b,t) | Linear interpolation of `a+t*(b-a)` |
| map(x,y,r,s,v) | Maps `v` from the range `[x,y]` to the range `[r,s]` |
| rand(a,b) | Random value between `[a,b)` |
| if(c,t,f) | Conditional, returning `t` if `c` > 0, `f` otherwise |

## Configs

The point after all, was to automatically set ConVars.

Currently the format is pretty simple, for each trigger, specify filters, formulas and commands like this:
```
"formula"
{
	"trigger"
	{
		"output1" "formula1"
		"output2" "formula2"
		"filter"
		{
			"condition1"
			{
				"output3" "formula3"
				"exec" "command1"
			}
		}
	}
}
```
There are a hand full of triggers by default, the will update all outputs with their associated formula. These are `OnMapStart`, `OnFormulasReloaded`, `OnRoundStart`, `OnPlayerJoined`, `OnPlayerParted`, `OnPlayerSpawn`, `OnPlayerDeath`, `EveryMinute`, but this list can be expanded by plugins.

The difference between `OnMapStart` and `OnFormulasReloaded` is that the former only executes once a map, while the later executes whenever the configs for this plugin are reloaded. This means if you initialize variables in `OnMapStart` you can tweak and reload the formulas without resetting values.

In addition to these default triggers there's also one default variable that will update automatically, and that's `$edicts`. While this plugin itself does not give entity count based triggers, this number might be helpful for other stuff as well.

Within `filter` you can list multiple blocks that will only trigger, if the condition the the name evaluates &gt;0. For example you could `"filter" { "$maptime-4" { "mp_autoteambalance" "if(@all-9,1,0)" } }` to set auto team balance if there are 10 or more players but only after minute 5 (inclusive).

You can also execute server commands. Instead of a cvar name just put `exec` and the command as value. You can put user variables into the command as well, but you have to prefix them with `i` for integer or `f` for numbers with decimals (floats). They should look something like `i$edicts`. Formulas, cvars and target selectors wont work here.

Besides a `default.cfg` config, you can create configs for every map (`mapname.cfg`). The configs should be located in your sourcemod directory under `/configs/formula/`.

## Commands

Use `sm_assign <output> <formula>` or `sm_formula <output> <formula>` to compute values and store the result in the output.
Outputs can be `$variables` that can be used by other formulas again, or ConVars.
Because this command can read and set ConVars, it requires the RCon admin-flag.

You can use `sm_eval <formula>` or `sm_calc <formula>` to compute values, the result is displayed to you.
This is available to all players, but only players with the RCon admin-flag can use ConVars!

If you need to reload the configs, use `sm_formula_reload`. This should keep all user variables, unless assigned in `OnFormulasReloaded`.

## Plugins

Not only can other plugins add triggers, they can also add calculations to triggers, listen to and manipulate user variables or simply use the math expression evaluator.

As plugin dev, please register your triggers before OnMapStart and fire your triggers after OnMapStart. That's because the configs for this plugin are loading OnMapStart.

## Future ideas

I don't know if or when I might implement these ideas, but it might be fun to:
- let other plugins add custom function for the math parser

## Example

```
"formula"
{
	// reduce gravity as game goes on
	"OnMapStart"
	{
		"sv_gravity" "800"
		"$maptime" "0"
	}
	"EveryMinute"
	{
		"$maptime" "$maptime+1"
		"sv_gravity" "map(0,mp_timelimit,800,100,$maptime)"
	}
	// half mvm damage when there are less than 7 players
	"OnPlayerJoined"
	{
		"tf_populator_health_multiplier" "if(@all-6,1,0.5)"
		"tf_populator_damage_multiplier" "if(@all-6,1,0.5)"
	}
	"OnPlayerParted"
	{
		"tf_populator_health_multiplier" "if(@all-6,1,0.5)"
		"tf_populator_damage_multiplier" "if(@all-6,1,0.5)"
	}
}
```

## Dependencies

No special dependencies, but chat colors will probably break in CSGO