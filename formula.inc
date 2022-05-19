#if defined __formula
#endinput
#endif
#define __formula

/**
 * Evaluate the formula passed get the result. Supportet operators are +,-,*,/ as well
 * as grouping () and some functions: min(a,b) max(a,b) abs(v) round(v) ceil(v) floor(v)
 * lerp(a,b,t) map(a,b,u,v,x) clamp(low,val,up) if(cond,then,else).
 * Note that if always checks cond>0. You have to rewrite your conditions to fit.
 * $variables will be used if present, @selectors will return the amount of matches
 * and convars will try to return their value.
 *
 * @param formula - the expression to evaluate
 * @param result - value returned
 * @param convars - can be used to controll access to convars
 * @param error,maxsize - out buffer for error messages if evaluation failed
 * @return true if evaluation succeded
 */
native bool Formula_Eval(const char[] formula, float& result, bool convars=true, char[] error="", int maxsize=0);

/* 
 * Set a variable name for evaluation. Using these variables in a formula requires
 * them to be prefixed by $. ConVars can not be set using this function.
 * Please note that the variable context is global and only global!
 * 
 * @param name - the variable name without $-prefix
 * @param value - the new value for this variable
 */
native void Formula_SetVariable(const char[] name, float value);
/**
 * Get the value for this variable. Variables that do not exist return 0.0
 * If you want to check whether the variable was set, use the isset-parameter.
 * Please note that the variable context is global and only global!
 *
 * @param name - the variable name without $-prefix
 * @param isset - will be true if the variable was set
 * @return the variables value or 0.0 if not set
 */
native float Formula_GetVariable(const char[] name, bool& isset=false);

/**
 * Called when a variable is changed through a formula.
 * This will only be called with changes caused by MathTriggers/Evaluators.
 * To prevent cyclic updates, these listeners will only be called the first
 * time a variable changes every gametick.
 *
 * @param name - the variable that changed
 * @param value - the new value
 */
forward void OnFormulaVariableChanged(const char[] name, float& value);

/**
 * Called when a trigger was dropped. This can happen when configs are reloaded
 * and all actions were forcefully removed from the trigger.
 * When you receive this forward, the passed trigger id is no longer valid under
 * the context that you obtained it and any further access is undefined behaviour.
 *
 * @param trigger - the trigger id that was dropped
 * @param name - the trigger name
 */
forward void OnFormulaTriggerDropped(int trigger, const char[] name);

/**
 * Represents the action of assigning a formula result to an output specified whenever fired
 */
methodmap Evaluator {
	/**
	 * Reevaluate the formula stored and assign it to the output again.
	 * All errors will be logged with LogError. For more control use Eval.
	 */
	public native void Fire();
	/**
	 * Set a filter for this Evaluator. Firing will have no effect if this filter failes.
	 * Set the filter to NULL_STRING to clear it
	 */
	public native void SetFilter(const char[] filter);
	/**
	 * Remove this Evaluation from it's associated trigger, freeing up the slot
	 */
	public native void Close();
}
/**
 * Represents an automated mechanism to update values
 */
methodmap MathTrigger {
	/**
	 * Create a new trigger or find an existing one by name.
	 * These names are created by plugins (Formula included) for other plugins to attach to.
	 * There's a maximum of 4095 triggers, if this limit is exceeded this method will throw.
	 *
	 * @param name - the trigger name, case sensitive
	 * @param locked - if true, only the owning plugin can fire this trigger
	 * @throw if 4095 other trigger are already registered
	 */
	public native MathTrigger(const char[] name);
	/**
	 * Attach a new Evaluator to this trigger.
	 * The output can be a $variable or convar, for the formula see Eval().
	 * There's a maximum of 1048575 evaluators, if this limit is exceeded this method will throw.
	 *
	 * @param output - the value storage for any results
	 * @param formula - the formula to compute
	 * @return a new Evaluator bound to this trigger
	 * @throw if 1048575 evaluators were already created
	 */
	#see Formula_Eval
	public native Evaluator AddFormula(const char[] output, const char[] formula);
	/**
	 * Trigger all Evaluators attached to this trigger.
	 * All errors will be logged with LogError. For more control use Eval.
	 */
	public native void Fire();
	/**
	 * Get all actions for the specified plugin source. Specify INVALID_HANDLE
	 * to retrieve evaluators for your plugin. If you do not specify an array list,
	 * only the evaluator count for this filter will be returned.
	 * 
	 * @param plugin - the plugin to filter evaluators on this trigger with
	 * @param evaluators - array list to collect evaluators for this trigger into
	 * @return the number of evaluators registered to this trigger by the plugin
	 */
	public native int GetEvaluators(Handle plugin=INVALID_HANDLE, ArrayList evaluators=null);
}

public SharedPlugin __pl_formula = {
    name = "formula",
    file = "formula.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_formula_SetNTVOptional() {
	MarkNativeAsOptional("Formula_Eval");
	MarkNativeAsOptional("Formula_SetVariable");
	MarkNativeAsOptional("Formula_GetVariable");
	MarkNativeAsOptional("Evaluator.Fire");
	MarkNativeAsOptional("Evaluator.Close");
	MarkNativeAsOptional("MathTrigger.MathTrigger");
	MarkNativeAsOptional("MathTrigger.AddFormula");
	MarkNativeAsOptional("MathTrigger.Fire");
	MarkNativeAsOptional("MathTrigger.GetEvaluators");
}
#endi