package com.memamsa.airdb
{
  /**
  * Author: Jacob Wright http://jacwright.com
  * Source: AIR ActiveRecord - 
  * http://code.google.com/p/air-activerecord/source/browse/trunk/src/flight/utils/Inflector.as
  **/
  
  /**
  * Word utilities to help map class names to tables and fields.
  * 
  * <p>The <code>Inflector</code> provides for transforming a ClassName into
  * underscored, humanized or camel-cased forms and vice-versa. It also includes
  * support for converting to and between singular and plural forms for common 
  * words.</p>
  * 
  * @example Some common examples
  * <listing version="3.0">
  * Inflector.underscore("ActionScript"); // "action_script"
  * Inflector.pluralize("Post");          // "Posts"
  * </listing>
  * 
  * @example The default mapping of a model class to its table
  * <listing version="3.0">
  * Inflector.underscore(Inflector.pluralize(className));
  * </listing>
  * 
  * @see DB#mapTable()
  **/
	public class Inflector
	{
		/**
		 * Returns the plural version of a word
		 **/
		public static function pluralize(word:String):String
		{
			for each (var rule:Array in pluralRules)
			{
				var regex:RegExp = rule[0];
				var replacement:String = rule[1];
				if (regex.test(word))
					return word.replace(regex, replacement);
			} 
			return word;
		}
		
		/**
		 * Gives back the singular version of a plural word
		 */
		public static function singularize(word:String):String
		{
			for each (var rule:Array in singularRules)
			{
				var regex:RegExp = rule[0];
				var replacement:String = rule[1];
				if (regex.test(word))
					return word.replace(regex, replacement);
			} 
			return word;
		}
		
		/**
		 * Camelizes an underscored phrase
		 */
		public static function camelize(word:String):String
		{
			return word.replace(camelizeExp, function(match:String, underScore:String, char:String, index:int, word:String):String
			{
				return char.toUpperCase();
			});
		}
		private static var camelizeExp:RegExp = /(^|_)(.)/g;
		
		/**
		 * Returns the underscore version of a phrase
		 */
		public static function underscore(word:String):String
		{
			return word.replace(underscoreExp1, "$1_$2").replace(underscoreExp2, "$1_$2").toLowerCase();
		}
		private static var underscoreExp1:RegExp = /([A-Z]+)([A-Z])/g;
		private static var underscoreExp2:RegExp = /([a-z])([A-Z])/g;
		
		/**
		 * Returns a the phrase as it would be read with spaces, optionally capitalizing the first
		 * character in each word
		 */
		public static function humanize(word:String, capitalize:Boolean = false):String
		{
			return underscore(word).replace(camelizeExp, function(match:String, underScore:String, char:String, index:int, word:String):String
			{
				return (index ? " " : "") + (capitalize ? char.toUpperCase() : char); // if this is the start of the string don't add the space
			});
		}
		
		/**
		 * Returns a phrase with all the words in it capitalized
		 */
		public static function upperWords(phrase:String):String
		{
			return phrase.replace(upperWordsExp, function(match:String, space:String, char:String, index:int, word:String):String
			{
				return space + char.toUpperCase();
			});
		}
		private static var upperWordsExp:RegExp = /(^| )(\w)/g;
		
		/**
		 * Returns a phrase with all the words in it not capitalized
		 */
		public static function lowerWords(phrase:String):String
		{
			return phrase.replace(upperWordsExp, function(match:String, space:String, char:String, index:int, word:String):String
			{
				return space + char.toLowerCase();
			});
		}
		
		/**
		 * Returns a phrase with only the first character capitalized
		 */
		public static function upperFirst(phrase:String):String
		{
			return phrase.charAt(0).toUpperCase() + phrase.substr(1);
		}
		
		/**
		 * Returns a phrase with only the first character lowercased
		 */
		public static function lowerFirst(phrase:String):String
		{
			return phrase.charAt(0).toLowerCase() + phrase.substr(1);
		}
		
		
		
		protected static var pluralRules:Array = [
			[/fish$/i, "fish"],						// fish
			[/(x|ch|ss|sh)$/i, "$1es"],				// search, switch, fix, box, process, address
			[/(series)$/i, "$1"],
			[/([^aeiouy]|qu)ies$/i, "$1y"],
			[/([^aeiouy]|qu)y$/i, "$1ies"],			// query, ability, agency
			[/(?:([^f])fe|([lr])f)$/i, "$1$2ves"],	// half, safe, wife
			[/sis$/i, "ses"],						// basis, diagnosis
			[/([ti])um$/i, "$1a"],					// datum, medium
			[/person$/i, "people"],					// person, salesperson
			[/man$/i, "men"],						// man, woman, spokesman
			[/child$/i, "children"],				// child
			[/media$/i, "media"],
			[/s$/i, "s"],							// no change (compatibility)
			[/$/, "s"]
		];
		
		protected static var singularRules:Array = [
			[/fish$/i, "fish"],
			[/(x|ch|ss|sh)es$/i, "$1"],
			[/movies$/i, "movie"],
			[/series$/i, "series"],
			[/([^aeiouy]|qu)ies$/i, "$1y"],
			[/([lr])ves$/i, "$1f"],
			[/(tive)s$/i, "$1"],
			[/([^f])ves$/i, "$1fe"],
			[/((a)naly|(b)a|(d)iagno|(p)arenthe|(p)rogno|(s)ynop|(t)he)ses$/i, "$1$2sis"],
			[/([ti])a$/i, "$1um"],
			[/people$/i, "person"],
			[/men$/i, "man"],
			[/status$/i, "status"],
			[/children$/i, "child"],
			[/news$/i, "news"],
			[/media$/i, "media"],
			[/s$/i, ""]
		];
	}
}