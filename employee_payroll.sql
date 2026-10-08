CREATE DATABASE IF NOT EXISTS PayrollDB;
USE PayrollDB;

-- ==========================================
-- 1. SCHEMA SETUP (TABLES)
-- ==========================================

CREATE TABLE Departments (
    department_id INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    manager_name VARCHAR(100) NOT NULL
);

CREATE TABLE Employees (
    emp_id INT AUTO_INCREMENT PRIMARY KEY,
    emp_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(15) UNIQUE,
    department_id INT,
    designation VARCHAR(50) NOT NULL,
    joining_date DATE NOT NULL,
    basic_salary DECIMAL(10, 2) CHECK (basic_salary > 0),
    FOREIGN KEY (department_id) REFERENCES Departments(department_id) ON DELETE SET NULL
);

CREATE TABLE Attendance (
    attendance_id INT AUTO_INCREMENT PRIMARY KEY,
    emp_id INT NOT NULL,
    attendance_date DATE NOT NULL,
    status ENUM('Present', 'Absent', 'Leave') NOT NULL DEFAULT 'Present',
    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE CASCADE,
    UNIQUE (emp_id, attendance_date) 
);

CREATE TABLE Leave_Record (
    leave_id INT AUTO_INCREMENT PRIMARY KEY,
    emp_id INT NOT NULL,
    leave_date DATE NOT NULL,
    leave_type VARCHAR(50) NOT NULL,
    reason TEXT,
    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE CASCADE
);

CREATE TABLE Salary (
    salary_id INT AUTO_INCREMENT PRIMARY KEY,
    emp_id INT NOT NULL,
    month_year VARCHAR(7) NOT NULL,
    working_days INT NOT NULL CHECK (working_days >= 0),
    present_days INT NOT NULL CHECK (present_days >= 0),
    deductions DECIMAL(10, 2) DEFAULT 0.00,
    bonus DECIMAL(10, 2) DEFAULT 0.00,
    final_salary DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE CASCADE,
    UNIQUE (emp_id, month_year) 
);

CREATE TABLE Attendance_Stats (
    emp_id INT,
    month_year VARCHAR(7),
    total_present INT DEFAULT 0,
    total_absent INT DEFAULT 0,
    PRIMARY KEY (emp_id, month_year),
    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE CASCADE
);

-- ==========================================
-- 2. VIEWS
-- ==========================================

CREATE VIEW VW_Employee_Attendance_Report AS
SELECT 
    e.emp_id, 
    e.emp_name, 
    d.department_name, 
    DATE_FORMAT(a.attendance_date, '%Y-%m') AS Month,
    COUNT(CASE WHEN a.status = 'Present' THEN 1 END) as Total_Present,
    COUNT(CASE WHEN a.status = 'Absent' THEN 1 END) as Total_Absent
FROM Employees e
JOIN Departments d ON e.department_id = d.department_id
LEFT JOIN Attendance a ON e.emp_id = a.emp_id
GROUP BY e.emp_id, e.emp_name, d.department_name, Month;

CREATE VIEW VW_Monthly_Payroll_Report AS
SELECT 
    s.month_year,
    e.emp_name,
    d.department_name,
    s.working_days,
    s.present_days,
    e.basic_salary,
    s.deductions,
    s.final_salary
FROM Salary s
JOIN Employees e ON s.emp_id = e.emp_id
JOIN Departments d ON e.department_id = d.department_id;

CREATE VIEW VW_Department_Salary_Analysis AS
SELECT 
    d.department_name,
    COUNT(e.emp_id) as Employee_Count,
    AVG(e.basic_salary) as Avg_Basic_Salary,
    SUM(s.final_salary) as Total_Expense
FROM Departments d
LEFT JOIN Employees e ON d.department_id = e.department_id
LEFT JOIN Salary s ON e.emp_id = s.emp_id
GROUP BY d.department_name;

-- ==========================================
-- 3. STORED PROCEDURES & TRIGGERS
-- ==========================================

DELIMITER //

CREATE PROCEDURE CalculateMonthlySalary(IN p_emp_id INT, IN p_month_year VARCHAR(7))
BEGIN
    DECLARE v_basic_salary DECIMAL(10, 2);
    DECLARE v_present_days INT;
    DECLARE v_working_days INT DEFAULT 22; 
    DECLARE v_deductions DECIMAL(10, 2) DEFAULT 0;
    DECLARE v_final_salary DECIMAL(10, 2);

    SELECT basic_salary INTO v_basic_salary FROM Employees WHERE emp_id = p_emp_id;

    SELECT COUNT(*) INTO v_present_days 
    FROM Attendance 
    WHERE emp_id = p_emp_id 
    AND DATE_FORMAT(attendance_date, '%Y-%m') = p_month_year 
    AND status = 'Present';

    IF v_present_days < v_working_days THEN
        SET v_deductions = (v_basic_salary / v_working_days) * (v_working_days - v_present_days);
    END IF;

    SET v_final_salary = v_basic_salary - v_deductions;

    INSERT INTO Salary (emp_id, month_year, working_days, present_days, deductions, final_salary)
    VALUES (p_emp_id, p_month_year, v_working_days, v_present_days, v_deductions, v_final_salary)
    ON DUPLICATE KEY UPDATE 
        present_days = v_present_days, 
        deductions = v_deductions, 
        final_salary = v_final_salary;
END //

CREATE TRIGGER Before_Attendance_Insert
BEFORE INSERT ON Attendance
FOR EACH ROW
BEGIN
    IF NEW.attendance_date > CURDATE() THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: Cannot log attendance for a future date.';
    END IF;
END //

CREATE TRIGGER After_Attendance_Insert
AFTER INSERT ON Attendance
FOR EACH ROW
BEGIN
    DECLARE v_month VARCHAR(7);
    SET v_month = DATE_FORMAT(NEW.attendance_date, '%Y-%m');
    
    INSERT INTO Attendance_Stats (emp_id, month_year, total_present, total_absent)
    VALUES (
        NEW.emp_id, 
        v_month, 
        IF(NEW.status = 'Present', 1, 0), 
        IF(NEW.status = 'Absent', 1, 0)
    )
    ON DUPLICATE KEY UPDATE 
        total_present = total_present + IF(NEW.status = 'Present', 1, 0),
        total_absent = total_absent + IF(NEW.status = 'Absent', 1, 0);
END //

DELIMITER ;

-- ==========================================
-- 4. INSERT DUMMY DATA
-- ==========================================

INSERT INTO Departments (department_name, manager_name) VALUES 
('Engineering', 'Alice Smith'),
('Human Resources', 'Bob Johnson'),
('Sales', 'Charlie Brown');

INSERT INTO Employees (emp_name, email, phone, department_id, designation, joining_date, basic_salary) VALUES
('John Doe', 'john@company.com', '555-0101', 1, 'Software Engineer', '2022-01-15', 80000),
('Jane Roe', 'jane@company.com', '555-0102', 1, 'Senior Engineer', '2021-03-10', 110000),
('Sam Fisher', 'sam@company.com', '555-0103', 2, 'HR Specialist', '2023-06-01', 60000);

INSERT INTO Leave_Record (emp_id, leave_date, leave_type, reason) VALUES
(1, '2023-10-15', 'Sick Leave', 'Flu');

INSERT INTO Attendance (emp_id, attendance_date, status) VALUES
(1, '2023-10-01', 'Present'), (1, '2023-10-02', 'Present'), (1, '2023-10-03', 'Absent'),
(2, '2023-10-01', 'Present'), (2, '2023-10-02', 'Present'), (2, '2023-10-03', 'Present'),
(3, '2023-10-01', 'Present'), (3, '2023-10-02', 'Absent');

-- Execute the procedure to generate a salary record for John Doe (emp_id 1) for October 2023
CALL CalculateMonthlySalary(1, '2023-10');
