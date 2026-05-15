# EHIAS — Electronic Hospital Information and Automation System

A relational database project built in MySQL that migrates a hospital's Excel-based records into a structured, integrity-enforced database system — complete with role-based access control, scheduling automation, and monthly reporting.

---

## Problem Statement

A hospital was managing all its records (patients, doctors, appointments, prescriptions, lab reports, and billing) using a flat Excel file. As operations scaled, this became error-prone and difficult to manage. The goal was to migrate this data into a robust relational database and implement business logic to solve six core problems.

---

## Problems Solved

| # | Problem | Solution |
|---|---|---|
| 1 | No unique identifiers | Primary keys with AUTO_INCREMENT on all tables |
| 2 | Disconnected relationships | Foreign key constraints across all related tables |
| 3 | Invalid or ambiguous data entries | CHECK constraints on Gender (M/F/O) and Status (Scheduled/Completed/Cancelled) |
| 4 | Unregulated scheduling | BEFORE INSERT trigger to block past appointments and double booking |
| 5 | Open access to sensitive patient data | Stored procedure with role-based access (senior vs junior doctors) |
| 6 | Disconnected reporting | Stored procedure for monthly revenue reports grouped by department |

---

## Database Schema

```
departments
    departmentID (PK)
    name

doctors
    doctorID (PK)
    name, specialization, role
    departmentID (FK → departments)

patients
    patientID (PK)
    name, DateofBirth, Gender, phone

appointment
    appointmentID (PK)
    patientID (FK → patients)
    doctorID (FK → doctors)
    appointmenttime, status

prescriptions
    prescriptionID (PK)
    appointmentID (FK → appointment)
    medication, dosage

labsreports
    reportID (PK)
    appointmentID (FK → appointment)
    reportdata, createdat

bills
    billID (PK)
    appointmentID (FK → appointment)
    amount, paid, billdate
```

---

## Files

| File | Description |
|---|---|
| `DATA_MIGRATION.sql` | Full SQL script: schema creation, data migration, trigger, and stored procedures |
| `hospital_data_10000_rows.csv` | Source flat file with 10,000 rows used for migration |
| `doctor_credentials.csv` | Doctor login credentials used by the access control procedure |

---

## How to Run

**Step 1: Load the source CSV as a staging table**

Import `hospital_data_10000_rows.csv` into MySQL as a table named `HOSPITAL_DATA` using MySQL Workbench's Table Data Import Wizard or the LOAD DATA INFILE command.

**Step 2: Load doctor credentials**

Import `doctor_credentials.csv` into MySQL as a table named `DOCTOR_CREDENTIALS`.

**Step 3: Run the SQL script**

Open `DATA_MIGRATION.sql` in MySQL Workbench and execute it in full. The script will:
- Create the EHIAS database and all tables
- Migrate data from HOSPITAL_DATA into normalized tables
- Create the scheduling trigger
- Create both stored procedures

---

## Key Features

### Trigger: CHECK_NEW_APPOINTMENT

Fires before every INSERT on the appointment table and blocks:
- Appointments scheduled in the past
- Double booking of the same doctor at the same time

### Stored Procedure: VIEW_DOCTOR_DATA

Accepts a username and password, validates credentials, and returns patient data based on the doctor's role:
- **Senior doctors** see all patients across their entire department
- **Junior doctors** see only their own patients

```sql
CALL VIEW_DOCTOR_DATA('doctor4', 'ic0pFSn0');
```

### Stored Procedure: SP_MONTHLYREVENUE

Generates a department-wise revenue summary for any given month and year.

```sql
CALL SP_MONTHLYREVENUE(2025, 5);
```

---

## Tech Stack

- MySQL 8.x
- MySQL Workbench
- CSV flat file as source data (10,000 rows)

---

## Author

**Garvit Mathur**
MCA Graduate | Data Analytics Enthusiast
[GitHub](https://github.com/tymepas)
