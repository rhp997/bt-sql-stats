SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET NOCOUNT ON
GO
IF OBJECT_ID('dbo.[1790BestFit]') IS NOT NULL
    DROP FUNCTION dbo.[1790BestFit]
GO
/* =============================================
  Author       : Steve Dodson
  Create date  : 6.Nov.2012
  Dependencies : 1790fnCurveFitting
  Description  : Runs the CurveFitting routine for each fit type and returns the highest correlated value
  Returns      : Returns a single data row solving for A, b, and R^2
  Parameters   : 
    @xCoords - Required - VARCHAR(MAX) - A comma-delimited string of x values
    @yCoords - Required - VARCHAR(MAX) - A comma-delimited string of y values

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
CREATE FUNCTION dbo.[1790BestFit]
(
    @xCoords VARCHAR(MAX),
    @yCoords VARCHAR(MAX)
)
RETURNS @p TABLE (Type TINYINT, A DECIMAL(38, 10), b DECIMAL(38, 10), R2 DECIMAL(38, 10))
AS
BEGIN
    /* Increment through fit types 1 - 4 with a recursive CTE */
    DECLARE @Start INT = 1, @End INT = 4 
    ;WITH incrementer(FitType, A, b, R2) as
    (
        SELECT 
            @Start [FitType], 
            t1.A,
            t1.b,
            t1.R2
        FROM dbo.[1790CurveFitting](@Start, @xCoords, @yCoords) t1
        UNION ALL
        SELECT 
            inc.FitType + 1, 
            t2.A,
            t2.b,
            t2.R2
        FROM incrementer inc 
        CROSS APPLY dbo.[1790CurveFitting](inc.FitType + 1, @xCoords, @yCoords) t2 
        WHERE inc.FitType < @End
    ) 
    /* And insert only the highest correlated row */
    INSERT @p
    SELECT TOP 1 FitType, A, b, R2
    FROM incrementer 
    WHERE R2 = (SELECT MAX(R2) FROM incrementer)

	RETURN
END
