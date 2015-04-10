SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET NOCOUNT ON
GO
IF OBJECT_ID('dbo.[1790StatisticsForXYSet]') IS NOT NULL
    DROP FUNCTION dbo.[1790StatisticsForXYSet]
GO
/* =============================================
  Author       : Steve Dodson
  Create date  : 8.Apr.2015
  Dependencies : [1790SplitString]
  Description  : Generic statistics calculations for the passed X/Y data set where X is used as the ID (see median 
                 calculation) and Y is the value being calculated. Thus, this function solves the y coordinates only;
                 the xCoords are superfluous and are only used/returned when the calculated median for the dataset 
                 is odd-numbered and corresponds to an ID in the x set (NULL when even-numbered). 
  Returns      : Returns a single data row solving for Median, Mean, Standard Deviation, Skewness, and Kurtosis
  Parameters   : 
    @Type    - Required - TINYINT      - Regression type; Linear (1), Exponential (2), Logarithmic (3), Power (4)
    @xCoords - Optional - VARCHAR(MAX) - A comma-delimited string of x values. If no value is passed, the rowid will 
                                         be used. Note this value is used as the "ID" or disambiguation field for the
                                         median calculation only.
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
CREATE FUNCTION dbo.[1790StatisticsForXYSet]
(
    @xCoords VARCHAR(MAX) = NULL,
    @yCoords VARCHAR(MAX)
)
RETURNS @stats TABLE (
    /* The x value (or row ID) corresponding to the calculated median; may be NULL if the dataset contains two median rows. */
    xID DECIMAL(38, 10) NULL,
    /* The center of the y values */
    Median DECIMAL(38, 10) NOT NULL,
    MaxValue DECIMAL(38, 10) NOT NULL,
    MinValue DECIMAL(38, 10) NOT NULL,
    /* The average of the y values */    
    Mean DECIMAL(38, 10) NOT NULL,
    NumRecords INT NOT NULL,
    /* The sum of the y values */    
    SumTotal DECIMAL(38, 10) NOT NULL,
    /* Sample standard deviation (n - 1); use when a portion of the data being studied has been 
       passed to this function */    
    StandardDev_Sample DECIMAL(38, 10) NOT NULL,
    /* Population standard deviation (n); use when the entirety of the data being studied has been 
       passed to this function. Slighly more accurate in such cases. */    
    StandardDev_Population DECIMAL(38, 10) NOT NULL,
    /* Skewness is a parameter that describes asymmetry in a random variables probability distribution. Skewness characterizes 
       the degree of asymmetry of a distribution around its mean. Positive skewness indicates a distribution with an asymmetric 
       tail extending toward more positive values. Negative skewness indicates a distribution with an asymmetric tail extending 
       toward more negative values (http://blogs.solidq.com/en/sqlserver/skewness-and-kurtosis-part-1-t-sql-solution/).
    */   
    /* Textual indicator of the possible (quick guess, not calculated) skewness direction. To be accurate, the skew 
       calculations done below should be compared to a table of normative values; this indicator simply compares the
       mean and median to arrive at a best guess. */
    Skew_Direction VARCHAR(20) NOT NULL,
    /* Corresponds to the MS Excel "Skew" formula = n / (n-1) / (n-2) * SUM(((x-µ)/s)3) */    
    Skew DECIMAL(38, 10) NOT NULL,
    /* Pearson 2 (median) skewness coefficient: compares the mean and median and indicates the standard 
       deviations apart the two measures of center are.  Possible values between -3 and 3 */
    Pearson2_Median_Skewness DECIMAL(38, 10) NOT NULL,
    /*
       Kurtosis characterizes the relative peakedness or flatness of a distribution compared with the normal distribution (mesokurtic). 
       Positive kurtosis (leptokurtic) indicates a relatively peaked distribution. Negative kurtosis (platykurtic) indicates a relatively 
       flat distribution. (http://blogs.solidq.com/en/sqlserver/skewness-and-kurtosis-part-1-t-sql-solution/)
    
       While related to skewness (data sets containing extreme values generally be both skewed and leptokurtic), Kurtosis is a separate 
       test for departure from the symmetric normal distribution.
    */
    /* Equivalent to the MS Excel KURT() function: 
        Kurt = n * (n+1) / (n-1) / (n-2) / (n-3) * SUM(((x-µ)/s)4)  3 * (n-1)2 / (n-2) / (n-3) */
    Kurtosis DECIMAL(38, 10) NOT NULL
)
AS
BEGIN
    DECLARE @CoordTable TABLE (
        x DECIMAL(38, 10) NOT NULL,
        y DECIMAL(38, 10) NOT NULL
    )

    /* If xCoords is NULL, use row number (ty.ID) as the x value */
    IF @xCoords IS NULL 
        INSERT INTO @CoordTable
        SELECT ty.ID, ty.TheWord
        FROM dbo.[1790SplitString](@yCoords, NULL, ',') ty
    ELSE
        INSERT INTO @CoordTable
        SELECT 
            CAST(tx.TheWord AS DECIMAL(38, 10)) [XValue], 
            CAST(tx.TheWord2 AS DECIMAL(38, 10)) [YValue]
        FROM dbo.[1790SplitString](@xCoords, @yCoords, ',') tx

    ;WITH AggCalcs (Mean, SumTotal, MaxValue, MinValue, StandardDev_Sample, StandardDev_Population, NumRecords, CorrFact1, CorrFact2, SubFact) AS (
        SELECT 
            AVG(ct.y) [Mean],
            SUM(ct.y) [SumTotal],
            MAX(ct.y) [MaxValue],
            MIN(ct.y) [MinValue],
            /* If the information being passed is the entirity of the dataset, use STDEVP; otherwise, is passed data 
               is a sample from a larger dataset, use STDEV. STDEV accounts for (n - 1) where STDEVP is n and more 
               accurate (assuming the data is complete). */
            STDEV(ct.y) [StandardDev_Sample],
            STDEVP(ct.y) [StandardDev_Population],
            COUNT(ct.y) [NumRecords],
            (COUNT(*) * 1.0 ) / (COUNT(*) - 1) / (COUNT(*) - 2) [CorrFact1],
            COUNT(*)*1.0 * (COUNT(*)+1) / (COUNT(*)-1) / (COUNT(*)-2) / (COUNT(*)-3) [CorrFact1],
            3.0 * SQUARE((COUNT(*)-1)) / (COUNT(*)-2) / (COUNT(*)-3) [SubFact]
        FROM @CoordTable ct
    )
    , OrderedRows(xID, yVal, RowAsc, RowDesc) AS (
        SELECT 
            ct.x,
            ct.y,
            ROW_NUMBER() OVER(ORDER BY ct.y ASC, ct.x ASC),
            ROW_NUMBER() OVER(ORDER BY ct.y DESC, ct.x DESC)
        FROM @CoordTable ct
        GROUP BY ct.x, ct.y
    ), MedianAll(xID, yVal) AS (
        /* Depending on dataset, may return multiple rows */
        SELECT 
            o.xID,
            o.yVal
        FROM OrderedRows o
        WHERE 
           o.RowAsc IN (o.RowDesc, o.RowDesc - 1, o.RowDesc + 1)
    )
    , Median(Median) AS (
        SELECT AVG(m.yVal) FROM MedianAll m
    )
    , Skewness(Skew_Direction, Skew, Pearson2_Median_Skewness) AS (
        SELECT 
            /* Subtract the Median from the Mean to get a guess as to the directional skew */
            CASE WHEN MAX(ag.Mean) = MAX(m.Median) THEN 'Symmetric' WHEN MAX(ag.Mean) > MAX(m.Median) THEN 'Positive (Right)' ELSE 'Negative (Left)' END [Calc_Skew_Dir],
            /* MS Excel "Skew" formula = n / (n-1) / (n-2) * SUM(((x-µ)/s)3) - Note this is calculated across the whole of the data unlike Pearson's which use summary values (mean, median) */
            SUM((((ct.y * 1.0) - ag.Mean)/ag.StandardDev_Sample)* (((ct.y * 1.0) - ag.Mean)/ag.StandardDev_Sample)* (((ct.y * 1.0) - ag.Mean)/ag.StandardDev_Sample)) * MAX(ag.CorrFact1) [Skew],
            /* Shows how many standard deviations apart the two measures of center are */
            3*((MAX(ag.Mean) - MAX(m.Median)) / MAX(ag.StandardDev_Sample)) [Pearson2_Median_Skewness]
        FROM @CoordTable ct
        CROSS JOIN AggCalcs ag
        CROSS JOIN Median m
    )
    , Kurtosis (Kurtosis) AS (
        /* Equivalent to the MS Excel KURT() function */
        SELECT SUM(SQUARE(SQUARE(((ct.y * 1.0 - ac.Mean) / ac.StandardDev_Sample)))) * MAX(ac.CorrFact2) - MAX(ac.SubFact)
        FROM @CoordTable ct, AggCalcs ac
    )
    INSERT INTO @stats
    SELECT 
        t1.xID,
        m.Median,
        ac.MaxValue,
        ac.MinValue,
        ac.Mean,
        ac.NumRecords,
        ac.SumTotal,
        ac.StandardDev_Sample,
        ac.StandardDev_Population,
        s.Skew_Direction,
        s.Skew,
        s.Pearson2_Median_Skewness,
        k.Kurtosis
    FROM AggCalcs ac, Skewness s, Kurtosis k, Median m
    /* For datasets with 2 median rows (i.e. even number of rows), the median is the average of those two rows and the xID is N/A.
       In such cases, instead of returning both rows with their associated xIDs, return NULL for the xID. When the dataset only has 
       a single median row (i.e. the calculated median equals the medianAll.yID), return the corresponding xID */
    LEFT OUTER JOIN (
        SELECT TOP 1 
            ma.xID, 
            ma.yVal 
        FROM MedianAll ma 
        ORDER BY ma.xID
    ) t1 ON t1.yVal = m.Median

    RETURN
END
