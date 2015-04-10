GO
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('dbo.[1790SplitString]') IS NOT NULL
    DROP FUNCTION dbo.[1790SplitString]
GO
/* =============================================
  Author       : Steve Dodson 
  Dependencies : None (SQL Server 2005 or greater)
  Description  : Splits the passed string using the passed delimiter, returning a dataset (with rowid) of the individual values. 
                 The second string parameter (TheString2) is optional; when passed, this is also parsed and the values matched to 
                 @TheString; thus, the values should correspond in number to the values as passed in @TheString and they will be 
                 returned as a matched pair. Thus, @TheString = '1,2,3' and @TheString2 = '3,2,1', the returned table will resemble:

                 ID TheWord    TheWord2
                 1     1           3
                 2     2           2
                 3     3           1
            
                 When the value is NULL, TheWord2 will be NULL. If the two @TheString params do not match in number, the smallest
                 matching dataset is returned - similar to an INNER JOIN. The second string param is ideal for efficiently parsing 
                 x,y values. For maximum compatibility, params and returned values are named after psiSplitString.
                 Adapted from David Wiseman's version here: http://www.wisesoft.co.uk/scripts/t-sql_cte_split_string_function.aspx
  Parameters   : 
    @TheString  - Required - VARCHAR(MAX) - The string to be parsed
    @TheString2 - Optional - VARCHAR(MAX) - Second string set to be parsed; when passed, should match @TheString in number of values
    @Delimiter  - Required - VARCHAR(5)   - Delimiter character(s)

    LICENSE:
    Copyright (C) 2015 Steve Dodson
    Email: support@dodsonlumber.com
    Full license text: https://github.com/rhp997/bt-sql-stats/blob/master/LICENSE

    This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as 
    published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software 
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

   ============================================= */
-- 
CREATE FUNCTION dbo.[1790SplitString]
(
	@TheString VARCHAR(MAX),
	@TheString2 VARCHAR(MAX) = NULL,    
	@Delimiter VARCHAR(5)
)  
RETURNS @RtnValue Table 
(
	ID INT,
	TheWord VARCHAR(100),
    TheWord2 VARCHAR(100)
) 
AS  
BEGIN 

	IF @TheString = '' OR @TheString IS NULL OR @Delimiter IS NULL
		RETURN

    /* Generating a rownumber in the CTE performs better than creating the ID column with IDENTITY(1,1) */
    ;WITH StringPos (RowNum, CurPos, NextPos, CurPos2, NextPos2) AS(
	    SELECT 
            1 [RowNum],
            CAST(0 AS BIGINT) AS CurPos,
            CHARINDEX(@Delimiter,@TheString) NextPos,
            CAST(0 AS BIGINT) AS CurPos2,
            CHARINDEX(@Delimiter,@TheString2) NextPos2
	    UNION ALL
	    SELECT 
            RowNum + 1,
            NextPos + 1,
            CHARINDEX(@Delimiter,@TheString,NextPos+1),
            NextPos2 + 1,
            CHARINDEX(@Delimiter,@TheString2,NextPos2 + 1)
	    FROM StringPos
	    WHERE NextPos > 0 AND ISNULL(NextPos2, 1) > 0
    )
    INSERT INTO @RtnValue
    SELECT 
        RowNum,
        SUBSTRING(@TheString, CurPos, COALESCE(NULLIF(NextPos, 0), LEN(@TheString) + 1) - CurPos) [TheWord],
        SUBSTRING(@TheString2, CurPos2, COALESCE(NULLIF(NextPos2, 0), LEN(@TheString2) + 1) - CurPos2) [TheWord2]
    FROM StringPos
    OPTION (MAXRECURSION 0)

	RETURN

END
