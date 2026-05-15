-- ============================================================
-- PROJECT   : EHIAS - Electronic Hospital Information and
--             Automation System
-- AUTHOR    : Garvit Mathur
-- DESCRIPTION: Full database creation, data migration from
--              flat CSV file, triggers, stored procedures
-- ============================================================

-- CREATE DATABASE
CREATE DATABASE EHIAS;
USE EHIAS;

-- ============================================================
-- SECTION 1: TABLE CREATION
-- ============================================================

-- CREATING DEPARTMENT TABLE
CREATE TABLE departments
(
    departmentID INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL
);

-- CREATING DOCTORS TABLE
CREATE TABLE doctors
(
    doctorID        INT AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(50),
    specialization  VARCHAR(100),
    role            VARCHAR(50),
    departmentID    INT,
    FOREIGN KEY (departmentID) REFERENCES departments(departmentID)
);

-- CREATING PATIENTS TABLE
CREATE TABLE patients
(
    patientID   INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(50),
    DateofBirth DATE,
    Gender      VARCHAR(1),
    phone       VARCHAR(15),
    CHECK (UPPER(Gender) IN ('M', 'F', 'O'))
);

-- CREATING APPOINTMENT TABLE
CREATE TABLE appointment
(
    appointmentID   INT AUTO_INCREMENT PRIMARY KEY,
    patientID       INT,
    doctorID        INT,
    appointmenttime DATETIME,
    status          VARCHAR(50),
    FOREIGN KEY (patientID) REFERENCES patients(patientID),
    FOREIGN KEY (doctorID)  REFERENCES doctors(doctorID),
    CHECK (status IN ('Scheduled', 'Completed', 'Cancelled'))
);

-- CREATING PRESCRIPTIONS TABLE
CREATE TABLE prescriptions
(
    prescriptionID  INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID   INT,
    medication      VARCHAR(100),
    dosage          VARCHAR(100),
    FOREIGN KEY (appointmentID) REFERENCES appointment(appointmentID)
);

-- CREATING BILLS TABLE
CREATE TABLE bills
(
    billID          INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID   INT,
    amount          DECIMAL(10,2),
    paid            TINYINT,
    billdate        DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointmentID) REFERENCES appointment(appointmentID)
);

-- CREATING LABSREPORTS TABLE
CREATE TABLE labsreports
(
    reportID        INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID   INT,
    reportdata      TEXT,
    createdat       DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointmentID) REFERENCES appointment(appointmentID)
);

-- ============================================================
-- SECTION 2: DATA MIGRATION FROM HOSPITAL_DATA FLAT FILE
-- NOTE: HOSPITAL_DATA is a staging table loaded from CSV.
--       Run each INSERT block after loading the CSV.
-- ============================================================

-- INSERT INTO DEPARTMENTS
INSERT INTO departments(departmentID, name)
SELECT `Departments.DepartmentID`, `Departments.Name`
FROM HOSPITAL_DATA
WHERE `Departments.DepartmentID` <> '';

-- INSERT INTO DOCTORS
INSERT INTO doctors(departmentID, doctorID, name, role, specialization)
SELECT `Doctors.DepartmentID`, `Doctors.DoctorID`, `Doctors.Name`,
       `Doctors.Role`, `Doctors.Specialization`
FROM HOSPITAL_DATA
WHERE `Doctors.DoctorID` <> '';

-- INSERT INTO PATIENTS
-- STR_TO_DATE handles DD-MM-YYYY format from the source CSV
INSERT INTO patients(DateofBirth, Gender, name, patientID, phone)
SELECT
    STR_TO_DATE(`Patients.DateOfBirth`, '%d-%m-%Y'),
    `Patients.Gender`,
    `Patients.Name`,
    `Patients.PatientID`,
    `Patients.Phone`
FROM HOSPITAL_DATA
WHERE `Patients.PatientID` <> '';

-- INSERT INTO APPOINTMENT
-- STR_TO_DATE handles DD-MM-YYYY HH:MM format from the source CSV
INSERT INTO appointment(appointmentID, appointmenttime, doctorID, patientID, status)
SELECT
    `Appointments.AppointmentID`,
    STR_TO_DATE(`Appointments.AppointmentTime`, '%d-%m-%Y %H:%i'),
    `Appointments.DoctorID`,
    `Appointments.PatientID`,
    `Appointments.Status`
FROM HOSPITAL_DATA
WHERE `Appointments.AppointmentID` <> '';

-- INSERT INTO PRESCRIPTIONS
INSERT INTO prescriptions(appointmentID, dosage, medication, prescriptionID)
SELECT `Prescriptions.AppointmentID`, `Prescriptions.Dosage`,
       `Prescriptions.Medication`, `Prescriptions.PrescriptionID`
FROM HOSPITAL_DATA
WHERE `Prescriptions.AppointmentID` <> '';

-- INSERT INTO LABSREPORTS
INSERT INTO labsreports(appointmentID, createdat, reportdata, reportID)
SELECT `LabReports.AppointmentID`, `LabReports.CreatedAt`,
       `LabReports.ReportData`, `LabReports.ReportID`
FROM HOSPITAL_DATA
WHERE `LabReports.AppointmentID` <> '';

-- INSERT INTO BILLS
INSERT INTO bills(amount, appointmentID, billdate, billID, paid)
SELECT `Bills.Amount`, `Bills.AppointmentID`, `Bills.BillDate`,
       `Bills.BillID`, `Bills.Paid`
FROM HOSPITAL_DATA
WHERE `Bills.BillID` <> '';

-- ============================================================
-- SECTION 3: VERIFICATION QUERIES
-- ============================================================

SELECT * FROM departments;
SELECT * FROM doctors;
SELECT * FROM patients;
SELECT * FROM appointment;
SELECT * FROM prescriptions;
SELECT * FROM labsreports;
SELECT * FROM bills;

-- ============================================================
-- SECTION 4: TRIGGER - UNREGULATED SCHEDULING
-- Prevents: appointments in the past and double booking
-- ============================================================

DROP TRIGGER IF EXISTS CHECK_NEW_APPOINTMENT;

DELIMITER $$

CREATE TRIGGER CHECK_NEW_APPOINTMENT
BEFORE INSERT ON APPOINTMENT
FOR EACH ROW
BEGIN
    -- RULE 1: Appointment cannot be scheduled in the past
    IF NEW.APPOINTMENTTIME < NOW() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: APPOINTMENT CANNOT BE IN THE PAST';
    END IF;

    -- RULE 2: Doctor cannot be double booked at the same time
    IF EXISTS
    (
        SELECT * FROM APPOINTMENT
        WHERE DOCTORID = NEW.DOCTORID
        AND APPOINTMENTTIME = NEW.APPOINTMENTTIME
        AND STATUS IN ('Scheduled')
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: DOCTOR ALREADY HAS AN APPOINTMENT AT THIS TIME';
    END IF;

END $$

DELIMITER ;

-- ============================================================
-- SECTION 5: STORED PROCEDURE - ROLE-BASED PATIENT DATA ACCESS
-- Senior doctors: see all patients in their department
-- Other doctors:  see only their own patients
-- ============================================================

DROP PROCEDURE IF EXISTS VIEW_DOCTOR_DATA;

DELIMITER $$

CREATE PROCEDURE VIEW_DOCTOR_DATA (IN INPUT_USERNAME VARCHAR(100), IN INPUT_PASSWORD VARCHAR(100))
BEGIN
    DECLARE DOC_ROLE VARCHAR(100);
    DECLARE DOC_DEPT INT;
    DECLARE DOC_ID   INT;

    -- STEP 1: VALIDATE CREDENTIALS AND GET DOCTOR ID
    SELECT DOCTORID INTO DOC_ID
    FROM DOCTOR_CREDENTIALS
    WHERE USER_NAME = INPUT_USERNAME AND PASSWORD = INPUT_PASSWORD;

    -- STEP 2: GET ROLE AND DEPARTMENT FOR THAT DOCTOR
    SELECT ROLE, DEPARTMENTID INTO DOC_ROLE, DOC_DEPT
    FROM DOCTORS
    WHERE DOCTORID = DOC_ID;

    -- STEP 3: RETURN DATA BASED ON ROLE
    IF DOC_ROLE = 'senior' THEN
        -- SENIOR DOCTORS: VIEW ALL PATIENTS IN THEIR DEPARTMENT
        SELECT
            D.DOCTORID,
            P.PATIENTID,
            P.NAME            AS 'PATIENT NAME',
            P.GENDER,
            A.APPOINTMENTTIME AS 'APPOINTMENT TIME',
            PR.MEDICATION,
            LR.REPORTDATA
        FROM PATIENTS AS P
        INNER JOIN APPOINTMENT   AS A  ON A.PATIENTID    = P.PATIENTID
        JOIN       DOCTORS       AS D  ON A.DOCTORID     = D.DOCTORID
        LEFT JOIN  PRESCRIPTIONS AS PR ON A.APPOINTMENTID = PR.APPOINTMENTID
        LEFT JOIN  LABSREPORTS   AS LR ON A.APPOINTMENTID = LR.APPOINTMENTID
        WHERE D.DEPARTMENTID = DOC_DEPT;

    ELSE
        -- JUNIOR DOCTORS: VIEW ONLY THEIR OWN PATIENTS
        SELECT
            A.DOCTORID,
            P.PATIENTID,
            P.NAME            AS 'PATIENT NAME',
            P.GENDER,
            A.APPOINTMENTTIME AS 'APPOINTMENT TIME',
            PR.MEDICATION,
            LR.REPORTDATA
        FROM PATIENTS AS P
        INNER JOIN APPOINTMENT   AS A  ON A.PATIENTID    = P.PATIENTID
        LEFT JOIN  PRESCRIPTIONS AS PR ON A.APPOINTMENTID = PR.APPOINTMENTID
        LEFT JOIN  LABSREPORTS   AS LR ON A.APPOINTMENTID = LR.APPOINTMENTID
        WHERE A.DOCTORID = DOC_ID;

    END IF;

END $$

DELIMITER ;

-- TEST CALL
-- CALL VIEW_DOCTOR_DATA('doctor4', 'ic0pFSn0');

-- ============================================================
-- SECTION 6: STORED PROCEDURE - MONTHLY REVENUE BY DEPARTMENT
-- ============================================================

DROP PROCEDURE IF EXISTS SP_MONTHLYREVENUE;

DELIMITER $$

CREATE PROCEDURE SP_MONTHLYREVENUE (IN P_YEAR INT, IN P_MONTH INT)
BEGIN
    SELECT
        DP.NAME          AS 'DEPARTMENT',
        SUM(B.AMOUNT)    AS TOTAL_REVENUE
    FROM BILLS AS B
    INNER JOIN APPOINTMENT  AS A  ON A.APPOINTMENTID  = B.APPOINTMENTID
    INNER JOIN DOCTORS      AS D  ON A.DOCTORID       = D.DOCTORID
    INNER JOIN DEPARTMENTS  AS DP ON DP.DEPARTMENTID  = D.DEPARTMENTID
    WHERE MONTH(B.BILLDATE) = P_MONTH
    AND   YEAR(B.BILLDATE)  = P_YEAR
    GROUP BY DP.NAME;
END $$

DELIMITER ;

-- TEST CALL
-- CALL SP_MONTHLYREVENUE(2025, 5);
