SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET NOCOUNT ON
GO
IF OBJECT_ID('dbo.[1790CurveFitting]') IS NOT NULL
    DROP FUNCTION dbo.[1790CurveFitting]
GO
/* =============================================
  Author       : Steve Dodson
  Create date  : 6.Nov.2012
  Dependencies : 1790SplitString
  Description  : Generic curve fitting calculation routine based on forum post found here: http://www.sqlteam.com/forums/topic.asp?TOPIC_ID=77311
                 Can be run for Linear, Exponential, Logarithmic, or Power curve fitting. Note that values (such as 0 or negative numbers) which
                 cannot be run through a LOG function will be excluded from the dataset. Pass 0 as the type to find the best fit (all other types
                 are tried and the highest R2 value is returned).
                 Fit types:
                    Type = 0 - Best fit (highest R2/correlation of the available options) 
                    Type = 1 - Linear (y = a + b*x | y = mx+b)
                    Type = 2 - Exponential (y = a*e^(b*x)   nb a > 0)
                    Type = 3 - Logarithmic (y = a + b*ln(x))
                    Type = 4 - Power (y = a*x^b	nb a > 0)
  Returns      : Returns a single data row solving for Y Intercept, Slope, and Correlation Coefficient
  Parameters   : 
    @Type    - Required - TINYINT      - Regression type; Linear (1), Exponential (2), Logarithmic (3), Power (4)
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
CREATE FUNCTION dbo.[1790CurveFitting]
(
	@Type TINYINT,
    @xCoords VARCHAR(MAX),
    @yCoords VARCHAR(MAX)
)
RETURNS @p TABLE (
    FitTypeID TINYINT NOT NULL,
    FitTypeName VARCHAR(15) NOT NULL,
    YIntercept DECIMAL(38, 10) NOT NULL, 
    Slope DECIMAL(38, 10) NOT NULL, 
    R2 DECIMAL(38, 10) NOT NULL
)
AS
BEGIN
	DECLARE	@n DECIMAL(38, 10), @x DECIMAL(38, 10), @x2 DECIMAL(38, 10), @y DECIMAL(38, 10), @xy DECIMAL(38, 10)
	DECLARE	@y2 DECIMAL(38, 10), @d DECIMAL(38, 10), @YIntercept DECIMAL(38, 10), @Slope DECIMAL(38, 10), @r2 DECIMAL(38, 10)

    DECLARE @CoordTable TABLE (
        x DECIMAL(38, 10) NOT NULL,
        y DECIMAL(38, 10) NOT NULL
    )
    
    IF @Type = 0 -- Best Fit
        /* Call dbo.[1790CurveFitting] recursively for types 1 - 4 and insert the highest correlated value */
        INSERT @p
        SELECT TOP 1 t2.FitTypeID, t2.FitTypeName, t2.YIntercept, t2.Slope, t2.R2
        FROM master..spt_values v
        CROSS APPLY dbo.[1790CurveFitting](v.number, @xCoords, @yCoords) t2 
        WHERE v.type='P' /* Type "P" (Projection) is simply a list of numbers between 0 and 1024 */
        AND v.number BETWEEN 1 AND 4 
        ORDER BY t2.R2 DESC
    ELSE
    BEGIN -- Types 1 - 4
        /* Populate an x/y grid table by splitting up the passed coords */
        INSERT INTO @CoordTable
        SELECT 
            CAST(tx.TheWord AS DECIMAL(38, 10)) [XValue], 
            CAST(tx.TheWord2 AS DECIMAL(38, 10)) [YValue]
        FROM dbo.[1790SplitString](@xCoords, @yCoords, ',') tx
        /*  Uncomment this section to quit whenever a 0 or negative number is encountered by a portion of the data set requiring a LOG calculation
            see also the "WHERE" clauses in the IF/THEN section below that eliminate 0 values
        -- Check for values that can't be LOGd (i.e. any number <= 0)
        IF ((@Type IN (2, 4)) AND ((SELECT y FROM @CoordTable WHERE y <= 0) IS NOT NULL))
            RETURN
        IF ((@Type IN (3, 4)) AND ((SELECT x FROM @CoordTable WHERE x <= 0) IS NOT NULL))
            RETURN */

        /* Notice the WHERE clause in ea. section eliminates values that cannot be subjected to the LOG function (i.e. <=0) 
           and may therefore exclude some datapoints in the calculation. If this is not the desired behaviour, uncomment the above section. */
        IF @Type = 2 -- Exponential
            SELECT
                @n = COUNT(*),
                @x = SUM(x),
                @x2 = SUM(x*x),
                @y = SUM(LOG(y)),
                @xy = SUM(x * LOG(y)),
                @y2 = SUM(LOG(y) * LOG(y))
            FROM @CoordTable
            WHERE y > 0
        ELSE IF @Type = 3 -- Logarithmic
            SELECT
                @n = COUNT(*),
                @x = SUM(LOG(x)),
                @x2 = SUM(LOG(x) * LOG(x)),
                @y = SUM(y),
                @xy = SUM(LOG(x) * y),
                @y2 = SUM(y*y)
            FROM @CoordTable
            WHERE x > 0
        ELSE IF @Type = 4 -- Power
            SELECT
                @n = COUNT(*),
                @x = SUM(LOG(x)),
                @x2 = SUM(LOG(x) * LOG(x)),
                @y = SUM(LOG(y)),
                @xy = SUM(LOG(x) * LOG(y)),
                @y2 = SUM(LOG(y) * LOG(y))
            FROM @CoordTable
            WHERE y > 0 
            AND x > 0
        ELSE -- Linear (default)
            SELECT
                @n = COUNT(*),
                @x = SUM(x),
                @x2 = SUM(x*x),
                @y = SUM(y),
                @xy = SUM(x*y),
                @y2 = SUM(y*y),
                @Type = 1 -- Explicity set type in case unsupported type passed
            FROM @CoordTable

        SET @d = @n * @x2 - @x * @x

	    IF @d = 0
		    RETURN

        -- Do the calculations
	    SELECT	
            @YIntercept = (@x2 * @y - @x * @xy) / @d,
		    @Slope = (@n * @xy - @x * @y) / @d,
		    @r2 = (@YIntercept * @y + @Slope * @xy - @y * @y / @n) / (@y2 - @y * @y / @n)

	    INSERT	@p
	    SELECT	
            @Type, 
            CASE @Type WHEN 2 THEN 'Exponential' WHEN 3 THEN 'Logarithmic' WHEN 4 THEN 'Power' ELSE 'Linear' END,
            CASE WHEN @Type IN (2, 4) THEN EXP(@YIntercept) ELSE @YIntercept END, @Slope, @r2
    END

	RETURN
END
