----BIẾN ĐỔI DỮ LIỆU 
-- (1) Thêm dữ liệu về Doanh số (của bảng Quantity_tab) vào bảng Sales 
-- (2) Thay đổi kiểu dữ liệu của cột
-- (3) lưu kết quả vào bảng View (phục vụ cho việc phân tích)
CREATE VIEW Sales_quantity_view AS
	SELECT CAST(s.[Sales Key] AS varchar) as [Sales Key]
			, CAST(s.[Purchase Date] AS Date) as [Purchase Date]
			, CAST(s.[Unit Price] AS decimal(10,2) ) as [Unit Price]
			, CAST(s.[Revenue] AS decimal(10,2) ) as Revenue
			, s.[Product Family]
			, s.[Product Department]
			, s.[Product Category]
			, s.Country
			, s.City
			, CAST(s.Weekday as INT)  as Weekday
			, CAST(s.[Day Purchase] as INT) as [Day Purchase]
			, CAST(s.[Month Purchase] as INT) as [Month Purchase]
			, CAST(s.[Quarter Purchase] as INT) as [Quarter Purchase]
			, CAST(s.[Year Purchase] as INT) as [Year Purchase] 
			, CAST(q.[Units Sold] as INT) as quantity 
FROM Sales s
LEFT JOIN Quantity_tab q
ON q.[Sales Key] = s.[Sales Key]



------TRẢ LỜI CÁC CÂU HỎI AD-HOC VÀ ĐƯA RA SỐ LIỆU -------

-- 1.Tổng doanh thu bán hàng cho mỗi tháng trong năm qua là bao nhiêu?

-- Khai báo biến và lấy năm gần nhất
DECLARE @MaxYear INT;
SELECT @MaxYear = MAX([Year Purchase]) 
FROM Sales_quantity_view;

-- Tính toán doanh thu hàng tháng và phần trăm đóng góp doanh thu
SELECT 
    [Month Purchase],
    SUM(revenue) AS monthly_revenue,
    SUM(revenue) * 100.0 / (
		SELECT SUM(revenue) 
		FROM Sales_quantity_view 
		WHERE [Year Purchase] = @MaxYear
		) AS pct_contribution
FROM 
    Sales_quantity_view
WHERE 
    [Year Purchase] = @MaxYear -- năm gần nhất
GROUP BY  
    [Month Purchase]
ORDER BY 
    [Month Purchase];

-- 2.Số lượng sản phẩm từng danh mục đã được bán trong quý vừa qua là bao nhiêu?
WITH cte1 AS 
(
	SELECT [Product Category]
		, SUM(quantity) as total_quantity
	FROM Sales_quantity_view
	WHERE [Quarter Purchase]  = (SELECT MAX([Quarter Purchase]) FROM Sales) -- điều kiện: quý vừa qua
	AND [Year Purchase] = ( SELECT MAX([Year Purchase]) FROM Sales_quantity_view )
	GROUP BY [Product Category]
)
SELECT *
	, total_quantity*100/ (SELECT SUM(total_quantity) FROM cte1) as pct_contribution 
FROM cte1 
ORDER BY total_quantity DESC

-- 3.Giá trung bình của các sản phẩm bán ra ở mỗi thành phố là bao nhiêu?
SELECT [Product Category], City
	, AVG([Unit Price]) as Avg_price
	, STDEV([Unit Price]) as Standard_deviation
FROM Sales_quantity_view 
WHERE [Year Purchase] = ( SELECT MAX([Year Purchase]) FROM Sales_quantity_view )
GROUP BY City, [Product Category]
ORDER BY 1 ASC, 4 DESC 

-- 4. Nhóm sản phẩm nào đã tạo ra doanh thu cao nhất trong năm qua?

SELECT TOP 1 [Product Department]
	, SUM(revenue) as total_revenue
FROM Sales_quantity_view
WHERE [Year Purchase] = (SELECT MAX([Year Purchase]) FROM Sales)  --- Điều kiện là năm gần nhất 
GROUP BY [Product Department]
ORDER BY SUM(revenue) DESC

-- 5. Xu hướng doanh số bán hàng của từng danh mục sản phẩm trong ba năm qua như thế nào?

WITH CTE as  ----- Tổng hợp doanh số bán hàng
(
	SELECT [Product Category], [Year Purchase],  SUM(quantity) as yearly_quantity
	FROM Sales_quantity_view 
	GROUP BY [Year Purchase], [Product Category]
)  
----- So sánh doanh số trung bình của tất cả sản phẩm trong 2 năm
SELECT [Year Purchase]
	, AVG(yearly_quantity) as Avg_quantity
FROM CTE 
GROUP BY [Year Purchase] 
-----Kết quả so sánh: Hầu hết các mặt hàng đều tăng doanh số trong năm 2016

-- 6. Hiệu suất bán hàng khác nhau giữa các ngày trong tuần và cuối tuần như thế nào?
WITH cte1 AS 
(
	SELECT [Year Purchase]
		, [Month Purchase]
		, Weekday
		, SUM(Quantity) as total_quantity
		, SUM(Revenue) as total_revenue
		, case when Weekday in (1,7) then 'weekend'
			else 'weekday'
		end as weekend_or_not
	FROM Sales
	GROUP BY [Year Purchase]
		, [Month Purchase]
		, Weekday
)
SELECT [Year Purchase]
	, weekend_or_not
	, AVG(total_quantity) as avg_daily_quantity
	, AVG(total_revenue) as avg_daily_revenue
FROM cte1 
GROUP BY [Year Purchase]
	, weekend_or_not
ORDER BY [Year Purchase]


-- 7. Khu vực địa lý nào đã cho thấy sự tăng trưởng cao nhất về doanh thu trong quý này (so với quý trước) ?
WITH cte2 AS --- Filter quý này và quý trước 
(
		SELECT TOP 2  [Quarter Purchase] 
		FROM (SELECT DISTINCT([Quarter Purchase]) FROM Sales_quantity_view) as get_distinct_quarter 
		ORDER BY [Quarter Purchase] DESC 
)
,cte3 AS --- Tính tổng doanh thu theo địa lý trong 2 quý gần nhất của năm nay 
(
	SELECT Country
		, City
		, [Quarter Purchase]
		, SUM(Revenue) as revenue_by_geo
	FROM Sales_quantity_view
	WHERE [Year Purchase] = (SELECT MAX([Year Purchase])  FROM Sales)
	AND [Quarter Purchase] in (SELECT * FROM cte2)
	GROUP BY Country, City, [Quarter Purchase]
) 
--- Tìm ra nơi nào có mức tăng trưởng revenue cao nhất
SELECT a.Country
		, a.City
		, a.revenue_by_geo as Q3_revenue
		, b.revenue_by_geo as Q4_revenue
		, ROUND((b.revenue_by_geo - a.revenue_by_geo)/a.revenue_by_geo*100,2) as revenue_growth
FROM cte3 a
LEFT JOIN (SELECT * FROM cte3 WHERE [Quarter Purchase] = 4) b
ON a.Country = b.Country
AND a.City = b.City
WHERE a.[Quarter Purchase] = 3
ORDER BY 5 DESC


-- 8. Phân phối doanh số bán hàng giữa các dòng sản phẩm (family product) khác nhau như thế nào?

---Tính total quantity của năm nay
WITH total_quantity_this_year AS
(
	SELECT SUM(Quantity) as total_quantity
	FROM Sales_quantity_view
	WHERE [Year Purchase] = (SELECT MAX([Year Purchase]) FROM Sales)
)
SELECT [Product Family]
	, SUM(Quantity) as total_quantity
	, SUM(Quantity)*100/ (SELECT total_quantity FROM total_quantity_this_year) as pct_quantity_contribution
FROM Sales_quantity_view
WHERE [Year Purchase] = (SELECT MAX([Year Purchase]) FROM Sales_quantity_view)
GROUP BY [Product Family]
ORDER BY 2 DESC

-- 9.Có bao nhiêu khách hàng đã mua hàng trong mỗi tháng của năm nay (năm gần nhất)?
SELECT [Month Purchase]
	, COUNT(DISTINCT([Sales Key])) as nbr_customers
FROM Sales_quantity_view
WHERE [Year Purchase] = (SELECT MAX([Year Purchase]) FROM Sales_quantity_view)
GROUP BY [Month Purchase]

-- 10. Phân nhóm khách hàng dựa vào RFM và lưu vào Datamart để chuẩn bị cho việc phân tích
---- Recency: số ngày tính từ lần cuối mua hàng đến ngày cuối cùng trong dataset
---- Frequency: tần suất mua hàng trung bình của khách hàng mỗi năm
---- Monetary: tổng số tiền trung bình khách hàng chi trả mỗi năm
WITH cte1 AS 
	(-- Tính 3 chỉ số của mô hình RFM
		SELECT [Sales Key]
			, DATEDIFF( day, MAX([Purchase Date]), (SELECT MAX([Purchase Date]) FROM Sales_quantity_view) ) as recency
			, COUNT([Sales Key])/ COUNT( DISTINCT([Year Purchase]) ) as frequency
			, SUM(Revenue)/ COUNT( DISTINCT([Year Purchase]) ) as monetary
		FROM Sales_quantity_view 
		GROUP BY [Sales Key]
	) 
, cte2 as -- Tính điểm R,F,M (dựa vào IQR)
	(
		SELECT *
			,NTILE(4) OVER (ORDER BY recency DESC) AS R
			,NTILE(4) OVER (ORDER BY frequency) AS F
			,NTILE(4) OVER (ORDER BY monetary) AS M
		FROM cte1 
	) 
-- Tạo tổ hợp từ việc ghép kết quả của các chỉ số
SELECT *
	,CONCAT(R,F,M) as combination
INTO RFM_model -- lưu bảng kết quả phân nhóm vào DataMart
FROM cte2 

-- TỪ BẢNG KẾT QUẢ RFM, TỔNG HỢP LẠI THEO TỔ HỢP, ĐỂ CHUẨN BỊ CHO VIỆC PHÂN TÍCH
SELECT combination
	,COUNT([sales key]) as nbr_customers -- Đếm số khách hàng trong 1 tổ hợp
	,SUM(monetary) as total_spending -- Tính tổng chi tiêu của từng tổ hợp mỗi năm
--INTO rfm_for_analysis  -- Lưu lại data cho việc phân tích
FROM RFM_model
GROUP BY combination
ORDER BY total_spending DESC

-- 11. Ở mỗi quốc gia, thì thành phố nào đạt doanh thu cao nhất (trong năm gần nhất)?
WITH cte1 AS ---(1) Tổng hợp doanh thu theo quốc gia và thành phố, rồi xếp hạng doanh thu
( 
		SELECT Country
			, City
			, SUM(Revenue) as total_revenue
			, DENSE_RANK() OVER ( PARTITION BY Country ORDER BY SUM(Revenue) DESC ) as ranking
		FROM Sales_quantity_view
		GROUP BY Country, City
) ---(2) Lấy ra thành phố có Doanh thu cao nhất ở mỗi quốc gia
SELECT *
FROM cte1 
WHERE ranking = 1

-- 12.Dòng sản phẩm chính (MAIN Product Department) của công ty là dòng nào (có nhiều lượt mua nhất), trong 2 năm gần nhất? 
----Mức tăng trưởng doanh thu như nào? 
----Làm sao để thúc đẩy thêm doanh thu dòng sản phẩm này?
WITH cte1 AS  --- (1) Tổng hợp Doanh số và Doanh thu, theo dòng sản phẩm
( 
	SELECT [Year Purchase]
		, [Product Department]
		, SUM(quantity) AS total_quantity 
		, SUM(Revenue) AS total_revenue
	FROM Sales_quantity_view
	WHERE [Year Purchase] IN ( SELECT DISTINCT Top 2 [Year Purchase] FROM Sales_quantity_view ORDER BY [Year Purchase] DESC)
	GROUP BY [Product Department], [Year Purchase] 
)
, cte2 as --- (2) Xếp hạng Doanh số trong mỗi năm
(
	SELECT *
		, DENSE_RANK() OVER (PARTITION BY [Year Purchase] ORDER BY total_quantity DESC) as ranking
	FROM cte1 
)  
--- (3) Lấy ra Dòng sản phẩm có doanh số cao nhất trong 2 năm gần đây, và tính mức tăng trưởng doanh thu
SELECT a.[Product Department] as main_prod_department
	, a.[total_quantity] as quantity_2015
	, a.[total_revenue] as revenue_2015
	, b.[total_quantity] as quantity_2016
	, b.[total_revenue] as revenue_2016
	, ROUND( (b.total_revenue - a.total_revenue)*100/ a.total_revenue , 2) as Revenue_growth
FROM cte2 a
LEFT JOIN (SELECT * FROM cte2 WHERE [Year Purchase] = 2016 and ranking = 1) b
ON a.[Product Department] = b.[Product Department]
WHERE a.ranking = 1 
AND a.[Year Purchase] = 2015

-- 13. Với mỗi doanh mục sản phẩm, Tổng hợp mức thay đổi về giá bán (YoY% Unit Price), trong 2 năm gần nhất?
WITH cte1 AS 
( ---(1) Lấy data của 2 năm gần nhất
		SELECT [Year Purchase]
			, [Product Category]
			, [Country]
			, [City]
			, [Unit Price]
		FROM Sales_quantity_view A
		WHERE [Year Purchase] IN ( 
						SELECT DISTINCT Top 2 [Year Purchase] 
						FROM Sales_quantity_view 
						ORDER BY [Year Purchase] DESC 
						)
) 
, cte2 AS
( ---(2) Biến đổi Dữ liệu: để có thêm cột Đơn giá của 2015 và 2016
		SELECT a.[Product Category]
			, a.[Country]
			, a.[City]
			, a.[Unit Price] as UnitPrice_2015
			, b.[Unit Price] as UnitPrice_2016
		FROM cte1 a
		LEFT JOIN (SELECT * FROM cte1 WHERE [Year Purchase] = 2016 ) b
		ON a.[Product Category] = b.[Product Category]
		AND a.Country = b.Country
		AND a.City = b.City
		WHERE a.[Year Purchase] = 2015
) --- Tính mức biến động trong giá bán của sản phẩm, tại các thành phố
SELECT [Product Category]
	, Country
	, City
	, AVG(UnitPrice_2015) as avg_UnitPrice2015
	, AVG(UnitPrice_2016) as avg_UnitPrice2016
	, ROUND( (AVG(UnitPrice_2016) - AVG(UnitPrice_2015) )*100 / AVG(UnitPrice_2015), 2 ) as YoY_UnitPrice
INTO YoY_Unitprice_2015_2016_ProductCategory
FROM cte2
GROUP BY [Product Category], Country, City


-- 14. Dòng sản phẩm nào (product department) có mức tăng trưởng thấp nhất? Làm sao để cải thiện?
DECLARE @Lowest_QuantityGrowth_ProductDepartment varchar(225)
WITH cte1 AS 
( --- Tổng hợp doanh số của Product Department theo từng năm
		SELECT [Product Department]
			, [Year Purchase] 
			, SUM(quantity) as total_quantity 
		FROM Sales_quantity_view
		WHERE [Year Purchase] IN ( 
				SELECT DISTINCT Top 2 [Year Purchase] 
				FROM Sales_quantity_view 
				ORDER BY [Year Purchase] DESC
				)
		GROUP BY [Product Department], [Year Purchase]
)
, cte2 AS 
( --- Tìm ra Product Department có mức tăng trưởng doanh số thấp nhất
		SELECT a.[Product Department]
			, a.total_quantity as quantity_2015
			, b.total_quantity as quantity_2016
			, (b.total_quantity - a.total_quantity)*100/ a.total_quantity as quantity_growth
		FROM cte1 a
		LEFT JOIN (SELECT * FROM cte1 WHERE [Year Purchase] = 2016) b
		ON a.[Product Department] = b.[Product Department]
		WHERE a.[Year Purchase] = 2015
)
SELECT TOP 1 @Lowest_QuantityGrowth_ProductDepartment = [Product Department]
FROM cte2 
ORDER BY quantity_growth ASC







