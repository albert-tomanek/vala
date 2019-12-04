/* valasymbol.vala
 *
 * Copyright (C) 2006-2018  Albert Tománek
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Albert Tománek <albert.tomanek@gmail.com>
 */

using GLib;

namespace Vala {
	/* The different linkage conventions that Vala can use */
	public enum Linkage {
		GOBJECT,	// This is default and what Vala uses currently
		CPP;

		public static Linkage parse(string str)
		{
			switch (str)
			{
				case "gobject":
					return GOBJECT;
				case "cpp":
					return CPP;
				default:
					assert_not_reached();
			}
		}
	}

	public errordomain ManglerError {
		FIELD_STARTS_WITH_DIGIT
	}

	public abstract class Mangler {
		public static Mangler for_linkage (Linkage lnkg)
		{
			switch (lnkg)
			{
				case Linkage.GOBJECT:
					return new Manglers.GObjMangler();
				case Linkage.CPP:
					return new Manglers.CppMangler();
				default:
					assert_not_reached();
			}
		}

		public abstract string mangle_constant (Constant sym);
		public abstract string mangle_field (Field sym) throws ManglerError;
		public abstract string mangle_creation_method (CreationMethod sym);
		public abstract string mangle_dynamic_method (DynamicMethod sym, ref int dynamic_method_id);
		public abstract string mangle_method (Method sym);
		public abstract string mangle_property_accessor (PropertyAccessor sym);
		public abstract string mangle_signal (Signal sym);
		public abstract string mangle_local_variable (LocalVariable sym);
		public abstract string mangle_parameter (Parameter sym);
	}

	/* This namespace contains a mangler class for each mangling convention */
	namespace Manglers {

		public class GObjMangler : Mangler {
			/**
			 * Mangles names using the gobject convention
			 * Most of this has been moved from `CCodeAttribute.get_default_name`.
			 */

			public override string mangle_constant (Constant sym)
			{
				if (sym.parent_symbol is Block) {
					// local constant
					return sym.name;
				}
				return "%s%s".printf (get_ccode_lower_case_prefix (sym.parent_symbol).ascii_up (), sym.name);
			}

			public override string mangle_field (Field sym)
			{
				var cname = sym.name;
				if (((Field) sym).binding == MemberBinding.STATIC) {
					cname = "%s%s".printf (get_ccode_lower_case_prefix (sym.parent_symbol), sym.name);
				}
				if (cname[0].isdigit ()) {
					throw new ManglerError.FIELD_STARTS_WITH_DIGIT("Field name starts with a digit. Use the `cname' attribute to provide a valid C name if intended");
				}
				return cname;
			}

			public override string mangle_creation_method (CreationMethod sym)
			{
				unowned CreationMethod m = (CreationMethod) sym;
				string infix;
				if (m.parent_symbol is Struct) {
					infix = "init";
				} else {
					infix = "new";
				}
				if (m.name == ".new") {
					return "%s%s".printf (get_ccode_lower_case_prefix (m.parent_symbol), infix);
				} else {
					return "%s%s_%s".printf (get_ccode_lower_case_prefix (m.parent_symbol), infix, m.name);
				}
			}

			public override string mangle_dynamic_method (DynamicMethod sym, ref int dynamic_method_id)
			{
				return "_dynamic_%s%d".printf (sym.name, dynamic_method_id++);
			}

			public override string mangle_method (Method m)
			{
				if (m.is_async_callback) {
					return "%s_co".printf (get_ccode_real_name ((Method) m.parent_symbol));
				}
				if (m.signal_reference != null) {
					return "%s%s".printf (get_ccode_lower_case_prefix (m.parent_symbol), get_ccode_lower_case_name (m.signal_reference));
				}
				if (m.name == "main" && m.parent_symbol.name == null) {
					// avoid conflict with generated main function
					return "_vala_main";
				} else if (m.name.has_prefix ("_")) {
					return "_%s%s".printf (get_ccode_lower_case_prefix (m.parent_symbol), m.name.substring (1));
				} else {
					return "%s%s".printf (get_ccode_lower_case_prefix (m.parent_symbol), m.name);
				}
			}

			public override string mangle_property_accessor (PropertyAccessor sym)
			{
				unowned PropertyAccessor acc = (PropertyAccessor) sym;
				var t = (TypeSymbol) acc.prop.parent_symbol;

				if (acc.readable) {
					return "%sget_%s".printf (get_ccode_lower_case_prefix (t), acc.prop.name);
				} else {
					return "%sset_%s".printf (get_ccode_lower_case_prefix (t), acc.prop.name);
				}
			}

			public override string mangle_signal (Signal sym)
			{
				return Symbol.camel_case_to_lower_case (sym.name).replace ("_", "-");
			}

			public override string mangle_local_variable (LocalVariable sym)
			{
				return sym.name;
			}

			public override string mangle_parameter (Parameter sym)
			{
				return sym.name;
			}
		}

		public class CppMangler : GObjMangler	// For symbols names that don't depend on the linkage scheme (such as signal names), the GLib/gobject ones are used, since that is what Vala uses internally.
		{
			/* Mangles names using the IA64 C++ ABI standard */
			/* https://itanium-cxx-abi.github.io/cxx-abi/abi.html#mangling */

			public override string mangle_method (Method meth)
			{
				StringBuilder mangled_name = new StringBuilder ("_Z");	// All C++ symbol names begin with a "_Z"

				/* Method name */

				if (meth.parent_symbol != null) {
					/* If the symbol is nested */

					mangled_name.append_c ('N');	// Indicates nested method

					/* Go up the symbol tree, prepending the names of all parent scopes. */
					var insert_pos = mangled_name.len;
					for (unowned Symbol? symbol = meth; symbol != null; symbol = symbol.parent_symbol)
					{
						mangled_name.insert(insert_pos, mangle_symbol_name(symbol));
					}

					mangled_name.append_c('E');		// End of nested method
				}
				else
				{
					mangled_name.append(mangle_symbol_name(meth));
				}

				/* Argument types */
				if (meth.get_parameters().size == 0)
				{
					/* If the method is void */
					mangled_name.append_c('v');
				}
				else
				{
					/* Append the type code for each argument to the mangled name */
					foreach (Parameter param in meth.get_parameters())
					{
						mangled_name.append(param.variable_type != null ? mangle_datatype(param.variable_type) : "Pv");		// IDK when the parameter wouldn't have a data type, but in the worst case pretend it's a pointer to void.
						print(mangle_datatype(param.variable_type) + "\n");
					}
				}

				return mangled_name.str;
			}

			/**
			 * Mangles a symbol name in the format `<length><name>`
			 */
			private static string mangle_symbol_name (Symbol symbol)
			{
				return symbol.name != null ? "%d%s".printf(symbol.name.length, symbol.name) : "";
			}

			/**
			 * May be a single letter for builtins, or a longer string for custom types.
			 */
			private static string mangle_datatype (DataType type)
			{

				if (type is ValueType)
				{
					switch (get_ccode_name (((ValueType) type).type_symbol))
					{
						/* Undefined-width integers */		// TODO: Would be nice to use the Vala.Struct `width` and `signed` attriutes to choose the letter instead of the literal type name...
						case "short":
							return "s";
						case "ushort":
							return "t";
						case "int":
							return "i";
						case "uint":
							return "j";
						case "long":
							return "l";
						case "ulong":
							return "m";

						/* Fixed-width integers. */
						// WARNING -- the characters may be wrong if the system has non-typical integer sizes, as the letters correspond to non-fixed-width integer types.
						case "int8":
							return "a";
						case "uint8":
							return "h";
						case "int16":
							return "s";
						case "uint16":
							return "t";
						case "int32":
							return "i";
						case "uint32":
							return "j";
						case "int64":
							return "l";
						case "uint64":
							return "m";
						default:
							printerr("Unknown: %s\n".printf(get_ccode_name (((ValueType) type).type_symbol)));
							break;
					}
				}
				else if (type is BooleanType)
				{
					return "b";
				}

				return "";
			}
		}
	}
}

vala-list@gnome.org
I'm writing a C++ mangler for Vala, and as part of this, I need to get the width and signedness of an IntegerType.
I've noticed from valaccodebasemodule.vala:433 that an IntegerType's `data_type` and `type_symbol` is a Vala.Struct, which has `width` and `signed` fields.
However, I've found that these are always 32, and true, regardless of the type of integer.
Also, nowhere in the source code can I find any descriptions of the integer types with their signdness and width. Does the vala compiler really just prepend a 'g' to the type name of integer variables?
And could you also please explain what the code at valaccodebasemodule.vala:433 does (ie. where all the given struct names are added to the root scope)?
Thanks
