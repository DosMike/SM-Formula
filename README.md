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

In addition to addition, subtraction, multiplication, division and modulo (remainder) you can also compare values logically using `<`,`<=`,`=`,`>=`,`>`,`<>` with the last one being inequality. These comparisons will result in 1.0 if the equation holds, and 0.0 if it doesnt. While you could use multiplication and addition to logically chain conditions, it's easier to use `&` for 'x and y' and `|` for 'x or y'. Especially using the following operation precedence, it makes writing conditions a lot more convenient (order first to last):
- Parentheses
- Multiplication, Division and Modulo
- Addition, Subtraction
- Comparisons (`<`,`<=`,`=`,`>=`,`>`,`<>`)
- Conjunction (and) and Disjunction (or) 

As a small little bonus the parser will also handle dice notation with syntax `int'd'int`, rolling a die with the right-hand number of pips left-hand times. `1d20` would give a value from 1 to 20; `3d4` would give 3 to 12 or `round(rand(1,4))+round(rand(1,4))+round(rand(1,4))`.

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

Within `filter` you can list multiple blocks that will only trigger, if the condition the the name evaluates &gt;0. For example you could `"filter" { "$maptime>=5" { "mp_autoteambalance" "if(@all>=10,1,0)" } }` to set auto team balance if there are 10 or more players but only after minute 5 (inclusive).

You can also execute server commands. Instead of a cvar name just put `exec` and the command as value. The commands support math context similar to `/mathexec`. Put math expressions between pund signs (`#`) to evaluate them. If you need integer values, round() them and decimals will not be appended. With this you could for example `sm_slap @all #round[rand[0,1]]#`. This will not work for setting convars unless you use the command `sm_cvar`!

Besides a `default.cfg` config, you can create configs for every map (`mapname.cfg`). The configs should be located in your sourcemod directory under `/configs/formula/`.

## Commands

Use `sm_assign <output> <formula>` or `sm_formula <output> <formula>` to compute values and store the result in the output.
Outputs can be `$variables` that can be used by other formulas again, or ConVars.
Because this command can read and set ConVars, it requires the RCon admin-flag.

You can use `sm_eval <formula>` or `sm_calc <formula>` to compute values, the result is displayed to you.
This is available to all players, but only players with the RCon admin-flag can use ConVars!

Another command is `sm_mathexec <commands>`. This is the command equivalent to exec entries in the config. You can specify math expressions within pound signs (`#`) to be evaluated. If you have the cvar admin flag you can use ConVar names as variables within those expressions. After evaluation the command will be run as client (unless called through server console), so permissions should be honored. If you need a literal `#` you can double it up as with the config. The example from above would now look something like `sm_mathexec sm_slap @all #round[rand[0,1]]#`

There's a set of commands similar to SourceMods plugin commands for managing configs.
- `sm_formula_list` will show all known and loaded configs. Names usually stick around until map change.
- `sm_formula_load <name>` will load a config if not already loaded.
- `sm_formula_reload` will nuke and reload default and map configs.
- `sm_formula_reload <name>` will only reload the specified config.
- `sm_formula_unload` will completely unload all configs.
- `sm_formula_unload <name>` will only unload the specified config.

Specify the config names relative to the `sourcemod/configs/formula/` directory. You can specify and organize configs in sub folders but don't add the `.cfg` extension for the commands. Unloading config will keep all user variables set by the config in memory until map change. These commands require the config admin flag (This should come as no surprise, you're un-/reloading configs here).

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