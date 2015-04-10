SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET NOCOUNT ON
GO
IF OBJECT_ID('dbo.[1790GetCurveFitCoords]') IS NOT NULL
    DROP FUNCTION dbo.[1790GetCurveFitCoords]
GO
/* =============================================
  Author       : Steve Dodson
  Create date  : 6.Nov.2012
  Dependencies : [1790CurveFitting], [1790SplitString]
  Description  : Given the slope, Y Intercept (both as returned by [1790CurveFitting]), and a series of x,y coordinates, this routine generates the 
                 coordinates of the passed trend line expanded by the value of @PtsBtwnXCoords (for visual smoothness).
  Returns      : Returns a single data row solving for Y Intercept, Slope, and Correlation Coefficient
  Parameters   : 
    @xCoords - Required - VARCHAR(MAX) - A comma-delimited string of NUMERIC x values. If wishing to plot the date on X, pass the day number or similar
    @yCoords - Required - VARCHAR(MAX) - A comma-delimited string of NUMERIC y values
    @Type    - Optional - TINYINT      - Regression type; Best Fit (0 - Default), Linear (1), Exponential (2), Logarithmic (3), Power (4)
    @CalcXTrend - Optional - BIT - Set to 1 to calculate the x coordinates of the trend line, NULL otherwise; disabled by default (calculation intensive)
    @CalcYTrend - Optional - BIT - Set to 1 to calculate the y coordinates of the trend line, NULL otherwise; enabled by default (calculation intensive)
    @PtsBtwnXCoords - Optional - TINYINT - Expand the original dataset by this number (0 = no expansion) to increase the smoothness of the line (Note: This is NOT
        a smoothing window). Rather, if your original graph has three points on the x-axis and you set this value to 7, seven additional x coordinates will be 
        generated at equal distance between points 1 and 2 and points 2 and 3. When plotted with the corresponding y values, the resulting line will appear smoother
        while maintaining the same trajectory / curve.

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
CREATE FUNCTION dbo.[1790GetCurveFitCoords]
(
    @xCoords VARCHAR(MAX),
    @yCoords VARCHAR(MAX),
	@Type TINYINT = NULL,
    @CalcXTrend BIT = NULL, 
    @CalcYTrend BIT = NULL, 
    @PtsBtwnXCoords TINYINT = NULL
)
RETURNS @ReturnCoords TABLE (
    FitTypeName VARCHAR(15) NOT NULL, -- Name of the curve fit type. Provided mainly as a means of generating a data label on a chart
    FitTypeID TINYINT NOT NULL, -- FitTypeID as passed
    yIntercept DECIMAL(38, 10) NOT NULL, -- Provided mainly as a means of generating a data label on a chart
    slope DECIMAL(38, 10) NOT NULL, -- Provided mainly as a means of generating a data label on a chart
    R2 DECIMAL(38, 10) NOT NULL, -- correlation coefficient. Provided mainly as a means of generating a data label on a chart
    x DECIMAL(38, 10) NOT NULL, -- expanded x value (see @PtsBtwnXCoords)
    y DECIMAL(38, 10) NOT NULL, -- expanded y value (see @PtsBtwnXCoords)
    xOriginal DECIMAL(38, 10) NOT NULL, -- Original x value prior to expansion
    yOriginal DECIMAL(38, 10) NOT NULL, -- Original x value prior to expansion
    xTrend DECIMAL(38, 10) NULL, -- Use with y (xTrend, y) to draw the trend line shown by fittypeid/name.  See also @CalcXTrend
    yTrend DECIMAL(38, 10) NULL  -- Use wit x (x, yTrend) to draw the trend line shown by fittypeid/name. See also @CalcYTrend
)
AS
BEGIN
    DECLARE @CoordTable TABLE (
        id INT NOT NULL,
        x DECIMAL(38, 10) NOT NULL,
        y DECIMAL(38, 10) NOT NULL,
        xOriginal DECIMAL(38, 10) NOT NULL,
        yOriginal DECIMAL(38, 10) NOT NULL,
        processed BIT NOT NULL
    )

    /* Initialize variables */
    SELECT 
        @PtsBtwnXCoords = ISNULL(@PtsBtwnXCoords, 0), /* This many points between each value; note, this is NOT a smoothing window */
        @CalcYTrend = ISNULL(@CalcYTrend, 1),
        @CalcXTrend = ISNULL(@CalcXTrend, 0),
        @Type = ISNULL(@Type, 0)

    /* Initially fill the coordinates table with original x/y values as passed to the sproc */
    INSERT INTO @CoordTable
    SELECT 
        ROW_NUMBER() OVER(ORDER BY tx.TheWord) [ID],
        CAST(tx.TheWord AS DECIMAL(38, 10)) [XValue], 
        CAST(tx.TheWord2 AS DECIMAL(38, 10)) [YValue],
        CAST(tx.TheWord AS DECIMAL(38, 10)) [OriginalXValue], 
        CAST(tx.TheWord2 AS DECIMAL(38, 10)) [OriginalYValue],    
        0 [Processed] /* Indicate original */
    FROM dbo.[1790SplitString](@xCoords, @yCoords, ',') tx    

    /* Insert a second data set into the mix expanding the result set by the value of @PtsBtwnXCoords. The new x,y values are calculated as percentages by
       subtracting the next x value from the current value and dividing by @PtsBtwnXCoords */
    INSERT INTO @CoordTable
    SELECT 
        ROW_NUMBER() OVER(ORDER BY ct.id, v.Number) [NewID],
        CASE v.number WHEN 1 THEN ct.x ELSE (((ct2.x - ct.x) / (@PtsBtwnXCoords + 1)) * (v.number - 1)) + ct.x END [x],
        CASE v.number WHEN 1 THEN ct.y ELSE (((ct2.y - ct.y) / (@PtsBtwnXCoords + 1)) * (v.number - 1)) + ct.y END [y],
        ct.x [OriginalX],
        ct.y [OriginalY],
        1 [Processed]
    FROM @CoordTable ct
    INNER JOIN @CoordTable ct2 ON ct2.id = ct.id + 1 -- Self join on the next ID to get the "next" row
    CROSS JOIN master..spt_values v
    WHERE v.type='P' /* Type "P" (Projection) is simply a list of numbers between 0 and 1024 */
    AND v.number BETWEEN 1 AND @PtsBtwnXCoords + 1
    AND ct.processed = 0

    /* The last row is excluded by the self-join; add it back here and set the id to the new (larger) value */
    UPDATE @CoordTable
    SET processed = 1, id = (SELECT MAX(id) + 1 FROM @CoordTable WHERE processed = 1)
    WHERE processed = 0 
    AND id = (SELECT MAX(id) FROM @CoordTable WHERE processed = 0)

    /* Remove the original data rows; the original x,y values are stored in columns and can easily be grouped out of the returned result */
    DELETE FROM @CoordTable WHERE processed = 0

    /* Create the final result set by calling the [1790CurveFitting] function, cross applying to the expanded coordinate set, and
       running the (fairly intensive) calculations to derive x,y coordinates for the trend line that is returned */
    INSERT INTO @ReturnCoords
    SELECT 
        cf.FitTypeName,
        cf.FitTypeID,
        cf.YIntercept,
        cf.slope,
        cf.R2,
        ct.x,
        ct.y,
        ct.xOriginal,
        ct.yOriginal,
        /* X and Y Trend values recreated using http://www.numberempire.com/equationsolver.php */
        CASE @CalcXTrend
          WHEN 1 THEN
            CASE cf.FitTypeID 
              WHEN 1 THEN (ct.y - cf.YIntercept) / cf.slope /* Linear, solve for x: x = (y - b) / m */
              WHEN 2 THEN LOG(ct.y / cf.YIntercept) / cf.slope /* Exponential, solve for x: x = log(y/a) / b */
              WHEN 3 THEN EXP(ct.y/cf.slope - cf.YIntercept/cf.slope) /* Logarithmic, solve for x: x = e^(y/b-a/b) */
              WHEN 4 THEN EXP(LOG(ct.y)/cf.slope - LOG(cf.YIntercept)/cf.slope) /* Power, solve for x: x = %e^(log(y)/b-log(A)/b) */
              ELSE 0 
            END
          ELSE NULL      
        END [xTrend], 
        CASE @CalcYTrend 
          WHEN 1 THEN
            CASE cf.FitTypeID 
              WHEN 1 THEN (cf.slope * ct.x) + cf.YIntercept /* Linear, solve for y: y = m(x) + b */
              WHEN 2 THEN cf.YIntercept * EXP(cf.slope * ct.x)   /* Exponential, solve for y: y = a*e^(b*x) */
              WHEN 3 THEN cf.YIntercept + cf.slope * LOG(ct.x) /* Logarithmic, solve for y: y = a + b*ln(x) */
              WHEN 4 THEN cf.YIntercept * POWER(ct.x, cf.slope) /* Power, solve for y: y = a*x^b */
              ELSE 0 
            END
          ELSE NULL
        END [yTrend]
    FROM dbo.[1790CurveFitting](@Type, @xCoords, @yCoords) cf
    CROSS JOIN @CoordTable ct
    WHERE (@Type = 3 AND ct.x > 0) /* Account for the various fit types and values <= 0 */
    OR (@Type = 2 AND ct.y > 0)
    OR (@Type = 4 AND ct.y > 0 AND ct.x > 0)
    OR (@Type IN (0, 1))
    ORDER BY ct.id

    RETURN
END
