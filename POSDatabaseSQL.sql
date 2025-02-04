IF DB_ID('SupermarketPOS') IS NULL
BEGIN
    CREATE DATABASE SupermarketPOS;
END
GO

USE SupermarketPOS;
GO

CREATE TABLE ProductCategory (
    CategoryID INT PRIMARY KEY IDENTITY(1,1),
    CategoryName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(255)
);


CREATE TABLE Product (
    ProductID INT PRIMARY KEY IDENTITY(1,1),
    ProductName NVARCHAR(100) NOT NULL,
    CategoryID INT NOT NULL,
    Description NVARCHAR(255),
    Barcode NVARCHAR(50) UNIQUE,
    FOREIGN KEY (CategoryID) REFERENCES ProductCategory(CategoryID)
);


CREATE TABLE Supplier (
    SupplierID INT PRIMARY KEY IDENTITY(1,1),
    Name NVARCHAR(100) NOT NULL,
    ContactInfo NVARCHAR(255),
    Address NVARCHAR(255)
);

CREATE TABLE ProductSupplier (
    ProductID INT NOT NULL,
    SupplierID INT NOT NULL,
    PRIMARY KEY (ProductID, SupplierID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    FOREIGN KEY (SupplierID) REFERENCES Supplier(SupplierID)
);
CREATE TABLE Branch (
    BranchID INT PRIMARY KEY IDENTITY(1,1),
    Name NVARCHAR(100) NOT NULL,
    Address NVARCHAR(255) NOT NULL,
    PhoneNumber NVARCHAR(20)
);

CREATE TABLE Employee (
    EmployeeID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Position NVARCHAR(50) NOT NULL,
    HireDate DATE NOT NULL,
    ManagerID INT,
    ContactInfo NVARCHAR(255),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    FOREIGN KEY (ManagerID) REFERENCES Employee(EmployeeID)
);


ALTER TABLE Branch
ADD ManagerID INT,
CONSTRAINT FK_Branch_Employee FOREIGN KEY (ManagerID) REFERENCES Employee(EmployeeID);

CREATE TABLE Customer (
    CustomerID INT PRIMARY KEY IDENTITY(1,1),
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100),
    Phone NVARCHAR(20),
    Address NVARCHAR(255),
    JoinDate DATE NOT NULL DEFAULT GETDATE()
);

CREATE TABLE Inventory (
    BranchID INT NOT NULL,
    ProductID INT NOT NULL,
    StockQuantity INT NOT NULL CHECK (StockQuantity >= 0),
    Price DECIMAL(10,2) NOT NULL CHECK (Price >= 0),
    PRIMARY KEY (BranchID, ProductID),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

CREATE TABLE PaymentMethod (
    PaymentMethodID INT PRIMARY KEY IDENTITY(1,1),
    MethodName NVARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE Sale (
    SaleID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    EmployeeID INT NOT NULL,
    CustomerID INT,
    SaleDateTime DATETIME NOT NULL DEFAULT GETDATE(),
    TotalAmount DECIMAL(10,2) NOT NULL CHECK (TotalAmount >= 0),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

CREATE TABLE SaleDetail (
    SaleDetailID INT PRIMARY KEY IDENTITY(1,1),
    SaleID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL CHECK (UnitPrice >= 0),
    Subtotal AS (Quantity * UnitPrice) PERSISTED,
    FOREIGN KEY (SaleID) REFERENCES Sale(SaleID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

CREATE TABLE SalePayment (
    SalePaymentID INT PRIMARY KEY IDENTITY(1,1),
    SaleID INT NOT NULL,
    PaymentMethodID INT NOT NULL,
    Amount DECIMAL(10,2) NOT NULL CHECK (Amount >= 0),
    FOREIGN KEY (SaleID) REFERENCES Sale(SaleID),
    FOREIGN KEY (PaymentMethodID) REFERENCES PaymentMethod(PaymentMethodID)
);
CREATE TABLE PurchaseOrder (
    PurchaseOrderID INT PRIMARY KEY IDENTITY(1,1),
    SupplierID INT NOT NULL,
    BranchID INT NOT NULL,
    OrderDate DATE NOT NULL DEFAULT GETDATE(),
    ExpectedDeliveryDate DATE,
    Status NVARCHAR(50) NOT NULL CHECK (Status IN ('Pending', 'Delivered', 'Cancelled')),
    FOREIGN KEY (SupplierID) REFERENCES Supplier(SupplierID),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);


CREATE TABLE PurchaseOrderDetail (
    PurchaseOrderDetailID INT PRIMARY KEY IDENTITY(1,1),
    PurchaseOrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitCost DECIMAL(10,2) NOT NULL CHECK (UnitCost >= 0),
    TotalCost AS (Quantity * UnitCost) PERSISTED,
    FOREIGN KEY (PurchaseOrderID) REFERENCES PurchaseOrder(PurchaseOrderID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

CREATE INDEX IX_Product_ProductName ON Product(ProductName);
CREATE INDEX IX_Product_Barcode ON Product(Barcode);
CREATE INDEX IX_Sale_SaleDateTime ON Sale(SaleDateTime);
CREATE INDEX IX_Customer_Email ON Customer(Email);
CREATE INDEX IX_Customer_Phone ON Customer(Phone);
CREATE INDEX IX_Employee_LastName ON Employee(LastName);
CREATE INDEX IX_Supplier_Name ON Supplier(Name);

CREATE TRIGGER TR_SaleDetail_AfterInsert
ON SaleDetail
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE inv
    SET StockQuantity = inv.StockQuantity - i.Quantity
    FROM Inventory inv
    INNER JOIN Sale s ON inv.BranchID = s.BranchID
    INNER JOIN inserted i ON s.SaleID = i.SaleID
    WHERE inv.ProductID = i.ProductID;
END;
 

CREATE TRIGGER TR_PurchaseOrder_AfterUpdate
ON PurchaseOrder
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF UPDATE(Status)
    BEGIN
        UPDATE inv
        SET StockQuantity = inv.StockQuantity + pod.Quantity
        FROM Inventory inv
        INNER JOIN PurchaseOrder po ON inv.BranchID = po.BranchID
        INNER JOIN PurchaseOrderDetail pod ON po.PurchaseOrderID = pod.PurchaseOrderID
        INNER JOIN inserted i ON po.PurchaseOrderID = i.PurchaseOrderID
        INNER JOIN deleted d ON po.PurchaseOrderID = d.PurchaseOrderID
        WHERE i.Status = 'Delivered' AND d.Status <> 'Delivered'
        AND inv.ProductID = pod.ProductID;
    END
END;


CREATE TABLE TaxType (
    TaxTypeID INT PRIMARY KEY IDENTITY(1,1),
    TaxName NVARCHAR(50) NOT NULL UNIQUE,
    Description NVARCHAR(255),
    IsPercentage BIT NOT NULL DEFAULT 1
);

CREATE TABLE TaxRate (
    TaxRateID INT PRIMARY KEY IDENTITY(1,1),
    TaxTypeID INT NOT NULL,
    Rate DECIMAL(5,2) NOT NULL CHECK (Rate >= 0),
    EffectiveDate DATE NOT NULL DEFAULT GETDATE(),
    EndDate DATE,
    BranchID INT NOT NULL,
    FOREIGN KEY (TaxTypeID) REFERENCES TaxType(TaxTypeID),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

CREATE TABLE ProductTax (
    ProductID INT NOT NULL,
    TaxTypeID INT NOT NULL,
    PRIMARY KEY (ProductID, TaxTypeID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    FOREIGN KEY (TaxTypeID) REFERENCES TaxType(TaxTypeID)
);
ALTER TABLE SaleDetail 
ADD TaxAmount DECIMAL(10,2) NOT NULL DEFAULT 0,  
    TotalWithTax AS ((Quantity * UnitPrice) + TaxAmount) PERSISTED;

ALTER TABLE PurchaseOrderDetail 
ADD TaxAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    TotalWithTax AS ((Quantity * UnitCost) + TaxAmount) PERSISTED;

	DROP TRIGGER IF EXISTS TR_SaleDetail_AfterInsert;

CREATE TRIGGER TR_SaleDetail_AfterInsert ON SaleDetail AFTER INSERT AS 
BEGIN
    SET NOCOUNT ON;

    -- Update Inventory
    UPDATE inv
    SET StockQuantity = inv.StockQuantity - i.Quantity
    FROM Inventory inv
    INNER JOIN Sale s ON inv.BranchID = s.BranchID
    INNER JOIN inserted i ON s.SaleID = i.SaleID
    WHERE inv.ProductID = i.ProductID;

    -- Calculate Taxes
    UPDATE sd
    SET TaxAmount = (
        SELECT 
            CASE WHEN tt.IsPercentage = 1
                THEN (i.Quantity * i.UnitPrice * tr.Rate / 100)
                ELSE (i.Quantity * tr.Rate)
            END
        FROM ProductTax pt
        JOIN TaxRate tr ON pt.TaxTypeID = tr.TaxTypeID
        JOIN TaxType tt ON tr.TaxTypeID = tt.TaxTypeID
        WHERE pt.ProductID = i.ProductID
        AND tr.BranchID = s.BranchID
        AND tr.EffectiveDate <= s.SaleDateTime
        AND (tr.EndDate IS NULL OR tr.EndDate >= s.SaleDateTime)
        -- Now, the aggregation part is avoided as the calculation is directly applied
    )
    FROM SaleDetail sd
    INNER JOIN inserted i ON sd.SaleDetailID = i.SaleDetailID
    INNER JOIN Sale s ON sd.SaleID = s.SaleID;
END;


ALTER TABLE Sale
ADD 
    TaxTotal DECIMAL(10, 2) NOT NULL DEFAULT 0,
    GrandTotal DECIMAL(10, 2) NOT NULL DEFAULT 0;

CREATE TRIGGER TR_Sale_AfterInsertUpdate
ON SaleDetail
AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;

    -- Update TaxTotal and GrandTotal in Sale table after Insert or Update in SaleDetail
    UPDATE s
    SET 
        s.TaxTotal = (SELECT SUM(sd.TaxAmount) 
                      FROM SaleDetail sd
                      WHERE sd.SaleID = s.SaleID),
        s.GrandTotal = (s.TotalAmount + 
                        (SELECT SUM(sd.TaxAmount) 
                         FROM SaleDetail sd 
                         WHERE sd.SaleID = s.SaleID))
    FROM Sale s
    INNER JOIN inserted i ON i.SaleID = s.SaleID
    WHERE s.SaleID = i.SaleID;
END;

CREATE TABLE [Return] (
    ReturnID INT PRIMARY KEY IDENTITY(1,1),
    SaleID INT NOT NULL,
    EmployeeID INT NOT NULL,
    ReturnDate DATETIME NOT NULL DEFAULT GETDATE(),
    TotalRefund DECIMAL(10,2) NOT NULL,
    Reason NVARCHAR(255),
    FOREIGN KEY (SaleID) REFERENCES Sale(SaleID),
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
);

CREATE TABLE ReturnDetail (
    ReturnDetailID INT PRIMARY KEY IDENTITY(1,1),
    ReturnID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    RefundAmount DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (ReturnID) REFERENCES [Return](ReturnID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

CREATE TABLE Discount (
    DiscountID INT PRIMARY KEY IDENTITY(1,1),
    DiscountName NVARCHAR(100) NOT NULL,
    DiscountType NVARCHAR(20) CHECK (DiscountType IN ('Percentage', 'Fixed')),
    Amount DECIMAL(10,2) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    BranchID INT,
    IsActive BIT DEFAULT 1,
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

CREATE TABLE ProductDiscount (
    ProductID INT NOT NULL,
    DiscountID INT NOT NULL,
    PRIMARY KEY (ProductID, DiscountID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    FOREIGN KEY (DiscountID) REFERENCES Discount(DiscountID)
);

CREATE TABLE LoyaltyProgram (
    LoyaltyID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL UNIQUE,
    PointsBalance INT NOT NULL DEFAULT 0,
    JoinDate DATE NOT NULL DEFAULT GETDATE(),
    LastRedemptionDate DATE,
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

CREATE TABLE Shift (
    ShiftID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    EmployeeID INT NOT NULL,
    StartTime DATETIME NOT NULL,
    EndTime DATETIME NOT NULL,
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
);

CREATE TABLE Shipment (
    ShipmentID INT PRIMARY KEY IDENTITY(1,1),
    PurchaseOrderID INT NOT NULL,
    DeliveryDate DATE,
    CarrierName NVARCHAR(100),
    TrackingNumber NVARCHAR(100),
    Status NVARCHAR(50) CHECK (Status IN ('In Transit', 'Delivered', 'Delayed')),
    FOREIGN KEY (PurchaseOrderID) REFERENCES PurchaseOrder(PurchaseOrderID)
);

CREATE TABLE Expense (
    ExpenseID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    ExpenseType NVARCHAR(50) CHECK (ExpenseType IN ('Utilities', 'Rent', 'Maintenance', 'Salaries')),
    Amount DECIMAL(10,2) NOT NULL,
    ExpenseDate DATE NOT NULL DEFAULT GETDATE(),
    Description NVARCHAR(255),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

CREATE TABLE AuditLog (
    LogID INT PRIMARY KEY IDENTITY(1,1),
    TableName NVARCHAR(100) NOT NULL,
    ActionType NVARCHAR(10) CHECK (ActionType IN ('INSERT', 'UPDATE', 'DELETE')),
    RecordID INT NOT NULL,
    UserID INT NOT NULL,
    ChangeDate DATETIME NOT NULL DEFAULT GETDATE(),
    OldValue NVARCHAR(MAX),
    NewValue NVARCHAR(MAX),
    FOREIGN KEY (UserID) REFERENCES Employee(EmployeeID)
);

CREATE TABLE StockAdjustment (
    AdjustmentID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    ProductID INT NOT NULL,
    AdjustmentDate DATETIME NOT NULL DEFAULT GETDATE(),
    PreviousQuantity INT NOT NULL,
    NewQuantity INT NOT NULL,
    Reason NVARCHAR(255),
    AuthorizedBy INT NOT NULL,
    FOREIGN KEY (BranchID, ProductID) REFERENCES Inventory(BranchID, ProductID),
    FOREIGN KEY (AuthorizedBy) REFERENCES Employee(EmployeeID)
);

CREATE TABLE PriceHistory (
    PriceHistoryID INT PRIMARY KEY IDENTITY(1,1),
    ProductID INT NOT NULL,
    BranchID INT NOT NULL,
    OldPrice DECIMAL(10,2) NOT NULL,
    NewPrice DECIMAL(10,2) NOT NULL,
    ChangeDate DATETIME NOT NULL DEFAULT GETDATE(),
    ChangedBy INT NOT NULL,
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    FOREIGN KEY (ChangedBy) REFERENCES Employee(EmployeeID)
);

CREATE TABLE Feedback (
    FeedbackID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    BranchID INT NOT NULL,
    FeedbackType NVARCHAR(20) CHECK (FeedbackType IN ('Complaint', 'Suggestion', 'Compliment')),
    Description NVARCHAR(MAX),
    Response NVARCHAR(MAX),
    Status NVARCHAR(20) CHECK (Status IN ('Open', 'In Progress', 'Resolved')),
    CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

CREATE TABLE UserAccount (
    UserID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT NOT NULL UNIQUE,
    Username NVARCHAR(50) NOT NULL UNIQUE,
    PasswordHash VARBINARY(256) NOT NULL,
    Role NVARCHAR(50) CHECK (Role IN ('Cashier', 'Manager', 'Admin')),
    LastLogin DATETIME,
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
);

CREATE INDEX IX_Return_SaleID ON [Return](SaleID);
CREATE INDEX IX_Discount_Dates ON Discount(StartDate, EndDate);
CREATE INDEX IX_Shipment_Status ON Shipment(Status);
CREATE INDEX IX_Expense_Type ON Expense(ExpenseType);
CREATE INDEX IX_PriceHistory_Date ON PriceHistory(ChangeDate);


-- Add Triggers
CREATE TRIGGER TR_PriceHistory_AfterUpdate
ON Inventory
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF UPDATE(Price)
    BEGIN
        INSERT INTO PriceHistory (ProductID, BranchID, OldPrice, NewPrice, ChangedBy)
        SELECT d.ProductID, d.BranchID, d.Price, i.Price, e.EmployeeID
        FROM inserted i
        INNER JOIN deleted d ON i.ProductID = d.ProductID AND i.BranchID = d.BranchID
        INNER JOIN Employee e ON e.BranchID = i.BranchID  -- Assuming current user context
        WHERE i.Price <> d.Price;
    END
END;


CREATE TRIGGER TR_LoyaltyPoints_AfterSale
ON Sale
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE lp
    SET lp.PointsBalance = lp.PointsBalance + (i.TotalAmount * 0.1) -- 1 point per $10 spent
    FROM LoyaltyProgram lp
    INNER JOIN inserted i ON lp.CustomerID = i.CustomerID
    WHERE i.CustomerID IS NOT NULL;
END;

CREATE TABLE SalaryStructure (
    StructureID INT PRIMARY KEY IDENTITY(1,1),
    Position NVARCHAR(50) NOT NULL UNIQUE,
    BaseSalary DECIMAL(10,2) NOT NULL,
    PayFrequency NVARCHAR(20) CHECK (PayFrequency IN ('Monthly', 'Bi-Weekly', 'Weekly')),
    OvertimeRate DECIMAL(5,2) NOT NULL DEFAULT 1.5,
    CommissionRate DECIMAL(5,2) DEFAULT 0,
    EffectiveDate DATE NOT NULL DEFAULT GETDATE(),
    CONSTRAINT CHK_SalaryStructure_Rates CHECK (
        OvertimeRate >= 1.0 AND 
        CommissionRate BETWEEN 0 AND 100
    )
);

CREATE TABLE EmployeeSalary (
    SalaryID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT NOT NULL UNIQUE,
    StructureID INT NOT NULL,
    BankAccount NVARCHAR(50),
    TaxDeductions DECIMAL(5,2) DEFAULT 0,
    OtherDeductions DECIMAL(10,2) DEFAULT 0,
    StartDate DATE NOT NULL,
    EndDate DATE,
    IsActive BIT DEFAULT 1,
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID),
    FOREIGN KEY (StructureID) REFERENCES SalaryStructure(StructureID),
    CONSTRAINT CHK_EmployeeSalary_Dates CHECK (EndDate > StartDate)
);

CREATE TABLE Payroll (
    PayrollID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    PayPeriodStart DATE NOT NULL,
    PayPeriodEnd DATE NOT NULL,
    ProcessDate DATE NOT NULL DEFAULT GETDATE(),
    TotalGross DECIMAL(12,2) NOT NULL,
    TotalDeductions DECIMAL(12,2) NOT NULL,
    TotalNet DECIMAL(12,2) NOT NULL,
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    CONSTRAINT CHK_Payroll_Amounts CHECK (
        TotalNet = TotalGross - TotalDeductions AND
        TotalGross >= 0 AND
        TotalDeductions >= 0
    )
);

CREATE TABLE PayrollDetail (
    PayrollDetailID INT PRIMARY KEY IDENTITY(1,1),
    PayrollID INT NOT NULL,
    EmployeeID INT NOT NULL,
    RegularHours DECIMAL(5,2),
    OvertimeHours DECIMAL(5,2),
    GrossPay DECIMAL(10,2) NOT NULL,
    Deductions DECIMAL(10,2) NOT NULL,
    NetPay DECIMAL(10,2) NOT NULL,
    PaymentMethodID INT NOT NULL,
    FOREIGN KEY (PayrollID) REFERENCES Payroll(PayrollID),
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID),
    FOREIGN KEY (PaymentMethodID) REFERENCES PaymentMethod(PaymentMethodID),
    CONSTRAINT CHK_PayrollDetail_Hours CHECK (
        RegularHours BETWEEN 0 AND 400 AND
        OvertimeHours BETWEEN 0 AND 100
    )
);

CREATE TABLE DeductionType (
    DeductionTypeID INT PRIMARY KEY IDENTITY(1,1),
    DeductionName NVARCHAR(50) NOT NULL,
    Description NVARCHAR(255),
    IsPercentage BIT NOT NULL,
    DefaultAmount DECIMAL(10,2),
    IsStatutory BIT NOT NULL DEFAULT 0
);


CREATE TABLE PayrollDeduction (
    PayrollDeductionID INT PRIMARY KEY IDENTITY(1,1),
    PayrollDetailID INT NOT NULL,
    DeductionTypeID INT NOT NULL,
    Amount DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (PayrollDetailID) REFERENCES PayrollDetail(PayrollDetailID),
    FOREIGN KEY (DeductionTypeID) REFERENCES DeductionType(DeductionTypeID)
);

CREATE TABLE Overtime (
    OvertimeID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT NOT NULL,
    DateWorked DATE NOT NULL,
    Hours DECIMAL(5,2) NOT NULL,
    ApprovedBy INT NOT NULL,
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID),
    FOREIGN KEY (ApprovedBy) REFERENCES Employee(EmployeeID),
    CONSTRAINT CHK_Overtime_Hours CHECK (Hours BETWEEN 0.5 AND 12)
);

CREATE TABLE Bonus (
    BonusID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT NOT NULL,
    Amount DECIMAL(10,2) NOT NULL,
    BonusDate DATE NOT NULL DEFAULT GETDATE(),
    Reason NVARCHAR(255),
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
);

CREATE INDEX IX_EmployeeSalary_Active ON EmployeeSalary(IsActive);
CREATE INDEX IX_Payroll_Period ON Payroll(PayPeriodStart, PayPeriodEnd);
CREATE INDEX IX_Overtime_Employee ON Overtime(EmployeeID, DateWorked);

CREATE TRIGGER TR_UpdateSalaryHistory
ON EmployeeSalary
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Mark previous salary as inactive
    UPDATE es
    SET es.IsActive = 0,
        es.EndDate = GETDATE()
    FROM EmployeeSalary es
    INNER JOIN inserted i ON es.EmployeeID = i.EmployeeID
    WHERE es.SalaryID <> i.SalaryID
    AND es.IsActive = 1;
END;

ALTER TABLE PayrollDetail
ADD PayPeriodStart DATE NOT NULL, 
    PayPeriodEnd DATE NOT NULL;

CREATE TRIGGER TR_CalculatePayrollDetail
ON PayrollDetail
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Update the PayrollDetail with the correct calculation
    UPDATE pd
    SET 
        pd.GrossPay = CASE
                        WHEN ss.PayFrequency = 'Monthly' THEN ss.BaseSalary
                        ELSE (pd.RegularHours * (ss.BaseSalary / 160)) + 
                             (pd.OvertimeHours * (ss.BaseSalary / 160) * ss.OvertimeRate)
                      END + ISNULL(b.BonusAmount, 0),
        pd.Deductions = (pd.GrossPay * es.TaxDeductions / 100) + es.OtherDeductions
    FROM PayrollDetail pd
    INNER JOIN EmployeeSalary es ON pd.EmployeeID = es.EmployeeID
    INNER JOIN SalaryStructure ss ON es.StructureID = ss.StructureID
    LEFT JOIN (
        SELECT b.EmployeeID, SUM(b.Amount) AS BonusAmount
        FROM Bonus b
        INNER JOIN inserted i ON b.EmployeeID = i.EmployeeID
        WHERE b.BonusDate BETWEEN i.PayPeriodStart AND i.PayPeriodEnd
        GROUP BY b.EmployeeID
    ) b ON pd.EmployeeID = b.EmployeeID
    INNER JOIN inserted i ON pd.PayrollDetailID = i.PayrollDetailID;
END;

CREATE TABLE AttendanceStatus (
    StatusID INT PRIMARY KEY IDENTITY(1,1),
    StatusName NVARCHAR(20) NOT NULL UNIQUE,
    Description NVARCHAR(255)
);
CREATE TABLE DailyAttendance (
    AttendanceID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT NOT NULL,
    AttendanceDate DATE NOT NULL DEFAULT GETDATE(),
    StatusID INT NOT NULL,
    CheckInTime TIME,
    CheckOutTime TIME,
    ShiftID INT,
    Remarks NVARCHAR(255),
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID),
    FOREIGN KEY (StatusID) REFERENCES AttendanceStatus(StatusID),
    FOREIGN KEY (ShiftID) REFERENCES Shift(ShiftID),
    CONSTRAINT CHK_AttendanceDate CHECK (AttendanceDate <= CAST(GETDATE() AS DATE))
);

CREATE TABLE MonthlyAttendanceSummary (
    SummaryID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT NOT NULL,
    MonthYear CHAR(7) NOT NULL, -- Format: 'YYYY-MM'
    TotalWorkingDays INT NOT NULL,
    TotalPresent INT NOT NULL DEFAULT 0,
    TotalAbsent INT NOT NULL DEFAULT 0,
    TotalLate INT NOT NULL DEFAULT 0,
    TotalLeaveDays INT NOT NULL DEFAULT 0,
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID),
    CONSTRAINT UQ_EmployeeMonthly UNIQUE (EmployeeID, MonthYear)
);

CREATE TABLE LeaveType (
    LeaveTypeID INT PRIMARY KEY IDENTITY(1,1),
    LeaveName NVARCHAR(50) NOT NULL,
    MaxDays INT NOT NULL
);

CREATE TABLE LeaveApplication (
    LeaveID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT NOT NULL,
    LeaveTypeID INT NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    Status NVARCHAR(20) CHECK (Status IN ('Pending', 'Approved', 'Rejected')),
    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID),
    FOREIGN KEY (LeaveTypeID) REFERENCES LeaveType(LeaveTypeID),
    CONSTRAINT CHK_LeaveDates CHECK (EndDate >= StartDate)
);


CREATE INDEX IX_DailyAttendance_Date ON DailyAttendance(AttendanceDate);
CREATE INDEX IX_MonthlySummary ON MonthlyAttendanceSummary(MonthYear);
CREATE INDEX IX_LeaveApplications ON LeaveApplication(EmployeeID, StartDate);


CREATE PROCEDURE GenerateMonthlyAttendanceSummary
    @MonthYear CHAR(7)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartDate DATE = DATEFROMPARTS(LEFT(@MonthYear, 4), RIGHT(@MonthYear, 2), 1);
    DECLARE @EndDate DATE = EOMONTH(@StartDate);
    
    -- Delete existing summary for the month
    DELETE FROM MonthlyAttendanceSummary 
    WHERE MonthYear = @MonthYear;
    
    -- Insert new summary
    INSERT INTO MonthlyAttendanceSummary (EmployeeID, MonthYear, TotalWorkingDays, 
        TotalPresent, TotalAbsent, TotalLate, TotalLeaveDays)
    SELECT 
        e.EmployeeID,
        @MonthYear,
        DATEDIFF(DAY, @StartDate, @EndDate) + 1 - ISNULL(h.Holidays, 0) AS TotalWorkingDays,
        SUM(CASE WHEN da.StatusID = 1 THEN 1 ELSE 0 END) AS TotalPresent,
        SUM(CASE WHEN da.StatusID = 2 THEN 1 ELSE 0 END) AS TotalAbsent,
        SUM(CASE WHEN da.StatusID = 3 THEN 1 ELSE 0 END) AS TotalLate,
        SUM(CASE WHEN da.StatusID = 5 THEN 1 ELSE 0 END) AS TotalLeaveDays
    FROM Employee e
    LEFT JOIN DailyAttendance da 
        ON e.EmployeeID = da.EmployeeID 
        AND da.AttendanceDate BETWEEN @StartDate AND @EndDate
    LEFT JOIN (
        SELECT BranchID, COUNT(*) AS Holidays
        FROM CompanyHoliday
        WHERE HolidayDate BETWEEN @StartDate AND @EndDate
        GROUP BY BranchID
    ) h ON e.BranchID = h.BranchID
    GROUP BY e.EmployeeID, h.Holidays;
END;

CREATE VIEW CurrentMonthAttendance AS
SELECT 
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName AS EmployeeName,
    FORMAT(da.AttendanceDate, 'dd-MM-yyyy') AS AttendanceDate,
    s.StatusName,
    da.CheckInTime,
    da.CheckOutTime,
    DATEDIFF(MINUTE, da.CheckInTime, da.CheckOutTime)/60.0 AS HoursWorked
FROM DailyAttendance da
JOIN Employee e ON da.EmployeeID = e.EmployeeID
JOIN AttendanceStatus s ON da.StatusID = s.StatusID
WHERE MONTH(da.AttendanceDate) = MONTH(GETDATE())
AND YEAR(da.AttendanceDate) = YEAR(GETDATE());


-- Trigger for Leave Applications
CREATE TRIGGER TR_UpdateLeaveDays
ON LeaveApplication
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF UPDATE(Status)
    BEGIN
        UPDATE da
        SET da.StatusID = 5 -- Leave status
        FROM DailyAttendance da
        JOIN inserted i 
            ON da.EmployeeID = i.EmployeeID
            AND da.AttendanceDate BETWEEN i.StartDate AND i.EndDate
        WHERE i.Status = 'Approved';
    END
END;

-- 1. Daily Financial Summary Table
CREATE TABLE DailyFinancialSummary (
    SummaryID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    SummaryDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    TotalSales DECIMAL(15,2) NOT NULL DEFAULT 0,
    TotalCost DECIMAL(15,2) NOT NULL DEFAULT 0,
    GrossProfit  AS (TotalSales - TotalCost),
    TotalExpenses DECIMAL(15,2) NOT NULL DEFAULT 0,
    NetProfit AS (TotalSales - TotalCost - TotalExpenses),
    CashBalance DECIMAL(15,2) NOT NULL DEFAULT 0,
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    CONSTRAINT UQ_DailySummary UNIQUE (BranchID, SummaryDate)
);

CREATE TABLE InventorySnapshot (
    SnapshotID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    ProductID INT NOT NULL,
    SnapshotDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    Quantity INT NOT NULL,
    CostValue DECIMAL(15,2) NOT NULL,
    RetailValue DECIMAL(15,2) NOT NULL,
    FOREIGN KEY (BranchID, ProductID) REFERENCES Inventory(BranchID, ProductID)
);

CREATE TABLE FinancialEvent (
    EventID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    EventDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    EventType NVARCHAR(50) CHECK (EventType IN ('StockReset', 'ProfitCalculation', 'Audit')),
    Description NVARCHAR(MAX),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);


-- Stored Procedure: Daily Closing Process
CREATE PROCEDURE ProcessDailyClosing
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today DATE = CAST(GETDATE() AS DATE);

    BEGIN TRANSACTION
    
    -- Calculate Daily Sales
    INSERT INTO DailyFinancialSummary (BranchID, SummaryDate, TotalSales, TotalCost, TotalExpenses)
    SELECT 
        @BranchID,
        @Today,
        ISNULL(SUM(sd.Subtotal), 0),
        ISNULL(SUM(sd.Quantity * pod.UnitCost), 0), -- COGS calculation
        ISNULL(SUM(e.Amount), 0)
    FROM Sale s
    LEFT JOIN SaleDetail sd ON s.SaleID = sd.SaleID
    LEFT JOIN PurchaseOrderDetail pod ON sd.ProductID = pod.ProductID
    LEFT JOIN Expense e ON s.BranchID = e.BranchID 
        AND CAST(e.ExpenseDate AS DATE) = @Today
    WHERE s.BranchID = @BranchID
        AND CAST(s.SaleDateTime AS DATE) = @Today

    -- Capture Inventory Snapshot
    INSERT INTO InventorySnapshot (BranchID, ProductID, SnapshotDate, Quantity, CostValue, RetailValue)
    SELECT 
        i.BranchID,
        i.ProductID,
        @Today,
        i.StockQuantity,
        i.StockQuantity * pod.UnitCost,
        i.StockQuantity * i.Price
    FROM Inventory i
    LEFT JOIN PurchaseOrderDetail pod ON i.ProductID = pod.ProductID
    WHERE i.BranchID = @BranchID

    -- Record Financial Event
    INSERT INTO FinancialEvent (BranchID, EventDate, EventType, Description)
    VALUES (@BranchID, @Today, 'ProfitCalculation', 
        CONCAT('Daily closing processed. Net Profit: $',
            (SELECT NetProfit FROM DailyFinancialSummary 
             WHERE BranchID = @BranchID AND SummaryDate = @Today))
    )

    COMMIT TRANSACTION
END;

ALTER TABLE SalePayment
ADD BranchID INT NOT NULL;  -- Ensure the column is not nullable

-- Optional: Add a foreign key constraint if it should reference the Branch table
ALTER TABLE SalePayment
ADD CONSTRAINT FK_SalePayment_Branch
FOREIGN KEY (BranchID) REFERENCES Branch(BranchID);



CREATE PROCEDURE CalculateDailyCashBalance
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today DATE = CAST(GETDATE() AS DATE);
    DECLARE @PreviousDay DATE = DATEADD(DAY, -1, @Today);
    DECLARE @PreviousCashBalance DECIMAL(15,2);

    -- Step 1: Get the Previous Day's Cash Balance
    SELECT @PreviousCashBalance = CashBalance
    FROM DailyFinancialSummary
    WHERE BranchID = @BranchID AND SummaryDate = @PreviousDay;

    -- If no record exists for previous day, set the Opening Cash Balance to 0
    IF @PreviousCashBalance IS NULL
    BEGIN
        SET @PreviousCashBalance = 0;
    END

    -- Step 2: Calculate the Cash Inflows (Sales)
    DECLARE @TotalSales DECIMAL(15,2);
    SELECT @TotalSales = ISNULL(SUM(TotalSales), 0)
    FROM DailyFinancialSummary
    WHERE BranchID = @BranchID AND SummaryDate = @Today;

    -- Step 3: Calculate the Cash Outflows (Total Costs and Expenses)
    DECLARE @TotalCost DECIMAL(15,2);
    DECLARE @TotalExpenses DECIMAL(15,2);
    SELECT @TotalCost = ISNULL(SUM(TotalCost), 0), @TotalExpenses = ISNULL(SUM(TotalExpenses), 0)
    FROM DailyFinancialSummary
    WHERE BranchID = @BranchID AND SummaryDate = @Today;

    -- Step 4: Calculate the Net Profit for the Day
    DECLARE @NetProfit DECIMAL(15,2);
    SET @NetProfit = @TotalSales - @TotalCost - @TotalExpenses;

    -- Step 5: Calculate the New Cash Balance
    DECLARE @NewCashBalance DECIMAL(15,2);
    SET @NewCashBalance = @PreviousCashBalance + @NetProfit;

    -- Step 6: Update the CashBalance for Today
    UPDATE DailyFinancialSummary
    SET CashBalance = @NewCashBalance
    WHERE BranchID = @BranchID AND SummaryDate = @Today;
END;


-- Trigger: Automatic Daily Process
CREATE TRIGGER TR_DailyClosingTrigger
ON SalePayment
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @LastSaleTime DATETIME = GETDATE()
    
    -- Check if it's end of business day (customize time as needed)
    IF FORMAT(@LastSaleTime, 'HH:mm') >= '20:00'
    BEGIN
        DECLARE @BranchID INT = (SELECT TOP 1 BranchID FROM inserted)
        
        EXEC ProcessDailyClosing @BranchID
		EXEC CalculateDailyCashBalance @BranchID
    END
END;

drop trigger TR_DailyClosingTrigger

-- View: Current Financial Position
CREATE VIEW CurrentFinancialPosition AS
SELECT
    b.Name AS Branch,
    dfs.SummaryDate,
    dfs.TotalSales,
    dfs.TotalCost,
    dfs.GrossProfit,
    dfs.TotalExpenses,
    dfs.NetProfit,
    dfs.CashBalance,
    SUM(isnap.RetailValue) AS RemainingStockValue
FROM DailyFinancialSummary dfs
JOIN Branch b ON dfs.BranchID = b.BranchID
JOIN InventorySnapshot isnap ON dfs.BranchID = isnap.BranchID
    AND dfs.SummaryDate = isnap.SnapshotDate
GROUP BY b.Name, dfs.SummaryDate, dfs.TotalSales, dfs.TotalCost, 
         dfs.GrossProfit, dfs.TotalExpenses, dfs.NetProfit, dfs.CashBalance;



		 -- Create SQL Agent Job to run at 23:59 daily
EXEC msdb.dbo.sp_add_job  
    @job_name = 'DailyFinancialClosing';

EXEC msdb.dbo.sp_add_jobstep  
    @job_name = 'DailyFinancialClosing',  
    @step_name = 'ProcessAllBranches',  
    @subsystem = 'TSQL',  
    @command = 'EXEC ProcessDailyClosing @BranchID = 1;  
                EXEC ProcessDailyClosing @BranchID = 2;
				EXEC ProcessDailyClosing @BranchID = 3;
				EXEC ProcessDailyClosing @BranchID = 4;
				EXEC ProcessDailyClosing @BranchID = 5;',  
    @retry_attempts = 3;



CREATE TABLE MonthlyFinancialSummary (
    SummaryID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    MonthYear CHAR(7) NOT NULL, -- Format: 'YYYY-MM'
    TotalSales DECIMAL(15,2) NOT NULL DEFAULT 0,
    TotalCost DECIMAL(15,2) NOT NULL DEFAULT 0,
    TotalExpenses DECIMAL(15,2) NOT NULL DEFAULT 0,
    OpeningCash DECIMAL(15,2) NOT NULL,
    ClosingCash DECIMAL(15,2) NOT NULL,
    OpeningStockValue DECIMAL(15,2) NOT NULL,
    ClosingStockValue DECIMAL(15,2) NOT NULL,
    GrossProfit AS (TotalSales - TotalCost),  -- Computed column
    NetProfit AS (TotalSales - TotalCost - TotalExpenses),  -- Computed column
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    CONSTRAINT UQ_MonthlySummary UNIQUE (BranchID, MonthYear)
);


CREATE TABLE MonthlyInventorySnapshot (
    SnapshotID INT PRIMARY KEY IDENTITY(1,1),
    BranchID INT NOT NULL,
    ProductID INT NOT NULL,
    MonthYear CHAR(7) NOT NULL,
    OpeningQuantity INT NOT NULL,
    ClosingQuantity INT NOT NULL,
    OpeningValue DECIMAL(15,2) NOT NULL,
    ClosingValue DECIMAL(15,2) NOT NULL,
    FOREIGN KEY (BranchID, ProductID) REFERENCES Inventory(BranchID, ProductID)
);



-- Stored Procedure: Monthly Closing Process
CREATE PROCEDURE ProcessMonthlyClosing
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PreviousMonth DATE = DATEADD(MONTH, -1, GETDATE());
    DECLARE @MonthYear CHAR(7) = FORMAT(@PreviousMonth, 'yyyy-MM');
    DECLARE @FirstDayOfMonth DATE = DATEFROMPARTS(YEAR(@PreviousMonth), MONTH(@PreviousMonth), 1);
    DECLARE @LastDayOfMonth DATE = EOMONTH(@PreviousMonth);

    BEGIN TRANSACTION
    
    -- Calculate Monthly Financial Summary
    INSERT INTO MonthlyFinancialSummary (
        BranchID,
        MonthYear,
        TotalSales,
        TotalCost,
        TotalExpenses,
        OpeningCash,
        ClosingCash,
        OpeningStockValue,
        ClosingStockValue
    )
    SELECT 
        @BranchID,
        @MonthYear,
        SUM(dfs.TotalSales),
        SUM(dfs.TotalCost),
        SUM(dfs.TotalExpenses),
        (SELECT TOP 1 CashBalance 
         FROM DailyFinancialSummary 
         WHERE BranchID = @BranchID 
           AND SummaryDate = @FirstDayOfMonth
         ORDER BY SummaryDate),
        (SELECT TOP 1 CashBalance 
         FROM DailyFinancialSummary 
         WHERE BranchID = @BranchID 
           AND SummaryDate = @LastDayOfMonth
         ORDER BY SummaryDate DESC),
        (SELECT SUM(RetailValue) 
         FROM InventorySnapshot 
         WHERE BranchID = @BranchID 
           AND SnapshotDate = @FirstDayOfMonth),
        (SELECT SUM(RetailValue) 
         FROM InventorySnapshot 
         WHERE BranchID = @BranchID 
           AND SnapshotDate = @LastDayOfMonth)
    FROM DailyFinancialSummary dfs
    WHERE BranchID = @BranchID
      AND SummaryDate BETWEEN @FirstDayOfMonth AND @LastDayOfMonth

    -- Create Monthly Inventory Snapshot
    INSERT INTO MonthlyInventorySnapshot (
        BranchID,
        ProductID,
        MonthYear,
        OpeningQuantity,
        ClosingQuantity,
        OpeningValue,
        ClosingValue
    )
    SELECT
        i.BranchID,
        i.ProductID,
        @MonthYear,
        (SELECT Quantity 
         FROM InventorySnapshot 
         WHERE ProductID = i.ProductID 
           AND BranchID = i.BranchID 
           AND SnapshotDate = @FirstDayOfMonth),
        (SELECT Quantity 
         FROM InventorySnapshot 
         WHERE ProductID = i.ProductID 
           AND BranchID = i.BranchID 
           AND SnapshotDate = @LastDayOfMonth),
        (SELECT CostValue 
         FROM InventorySnapshot 
         WHERE ProductID = i.ProductID 
           AND BranchID = i.BranchID 
           AND SnapshotDate = @FirstDayOfMonth),
        (SELECT RetailValue 
         FROM InventorySnapshot 
         WHERE ProductID = i.ProductID 
           AND BranchID = i.BranchID 
           AND SnapshotDate = @LastDayOfMonth)
    FROM Inventory i
    WHERE BranchID = @BranchID

    -- Record Financial Event
    INSERT INTO FinancialEvent (BranchID, EventDate, EventType, Description)
    VALUES (@BranchID, GETDATE(), 'MonthlyClosing', 
        CONCAT('Monthly closing processed for ', @MonthYear, 
               '. Net Profit: $', (SELECT NetProfit 
                                  FROM MonthlyFinancialSummary 
                                  WHERE BranchID = @BranchID 
                                    AND MonthYear = @MonthYear))
    )

    COMMIT TRANSACTION
END;




-- SQL Agent Job Configuration (Run on 1st of every month)
EXEC msdb.dbo.sp_add_job  
    @job_name = 'MonthlyFinancialClosing';

EXEC msdb.dbo.sp_add_jobstep  
    @job_name = 'MonthlyFinancialClosing',  
    @step_name = 'ProcessAllBranches',  
    @subsystem = 'TSQL',  
    @command = 'EXEC ProcessMonthlyClosing @BranchID = 1;
                EXEC ProcessMonthlyClosing @BranchID = 2;
				EXEC ProcessMonthlyClosing @BranchID = 3;
				EXEC ProcessMonthlyClosing @BranchID = 4;
				EXEC ProcessMonthlyClosing @BranchID = 5;',  
    @retry_attempts = 3;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = 'FirstDayOfMonth',
    @freq_type = 16,               -- Monthly
    @freq_interval = 1,            -- First day of the month
    @freq_recurrence_factor = 1,   -- Repeat every 1 month
    @active_start_time = 233000;    -- 23:30:00

EXEC msdb.dbo.sp_attach_schedule  
    @job_name = 'MonthlyFinancialClosing',  
    @schedule_name = 'FirstDayOfMonth';