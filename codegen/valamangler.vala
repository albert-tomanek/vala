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
		GOBJECT;	// This is default and what Vala uses currently
		CPP;
	}

	public class Mangler {
		public abstract static string mangle_subroutine(Subroutine subr);
	}

	/* This namespace contains a mangler class for each mangling convention */
	namespace Manglers {
		public class GObjMangler : Mangler {
			/* Mangles names using the gobject convention */

			public override static string mangle_subroutine (Subroutine subr)
			{
				StringBuilder mangled_name = new StringBuilder ();

				for (unowned Symbol? symbol = subr; symbol != null; symbol = symbol.parent_scope)
				{
					mangled_name.prepend(symbol.name);

					if (symbol.parent_scope != null)
						mangled_name.prepend_c('_');
				}

				return mangled_name;
			}
		}

		public class CppMangler : Mangler {
			/* Mangles names using the IA64 C++ ABI standard */
			/* https://itanium-cxx-abi.github.io/cxx-abi/abi.html#mangling */

			public override static string mangle_subroutine (Subroutine subr)
			{
				StringBuilder mangled_name = new StringBuilder ("_Z");	// All C++ symbol names begin with a "_Z"

				/* Subroutine name */

				if (subr.parent_symbol != NULL) {
					/* If the symbol is nested */

					mangled_name.append_c ('N');	// Indicates nested method

					/* Go up the symbol tree, prepending the names of all parent scopes. */
					int insert_pos = mangled_name.len;
					for (unowned Symbol? symbol = subr; symbol != null; symbol = symbol.parent_scope)
					{
						mangled_name.insert(insert_pos, mangle_symbol_name(symbol));
					}

					mangled_name.append_c('E');		// End of nested method
				}
				else
				{
					mangled_name.append(mangle_symbol_name(symbol));
				}

				/* Argument types */
				if (!subr.has_result)
				{
					/* If the method is void */
					mangled_name.append_c('v');
				}
				else
				{
					printerr("Non-void method\n");
				}

				return mangled_name.str;
			}

			/**
			 * Mangles a symbol name in the format `<length><name>`
			 */
			private static string mangle_symbol_name (Symbol symbol)
			{
				return "%d%s".printf(symbol.name.length, symbol.name);
			}
		}
	}
}
