using System.Text.RegularExpressions;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;

public class Functions {
    [SqlFunction(Name = "CLR_RegExp_like", DataAccess = DataAccessKind.None,
                 IsDeterministic = true)]
    public static SqlBoolean RegEx_Match(SqlString input, SqlString pattern) {
       if (input.IsNull || pattern.IsNull || input.ToString().Length == 0 ||
           pattern.ToString().Length == 0)
           return SqlBoolean.Null;
       return Regex.IsMatch(input.ToString(), pattern.ToString());
    }
}