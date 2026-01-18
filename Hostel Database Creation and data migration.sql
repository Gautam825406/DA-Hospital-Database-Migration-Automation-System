-- ===============================
-- DATABASE
-- ===============================
CREATE DATABASE ehias;
USE EHIAS;

-- ===============================
-- DEPARTMENTS
-- ===============================
CREATE TABLE departments (
  departmentid INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL
);

-- ===============================
-- DOCTORS
-- ===============================
CREATE TABLE doctors (
  doctorid INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50),
  specialization VARCHAR(100),
  role VARCHAR(50),
  departmentid INT,
  FOREIGN KEY (departmentid) REFERENCES departments(departmentid)
);

-- ===============================
-- PATIENTS
-- ===============================
CREATE TABLE patients (
  patientid INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50),
  dateofbirth DATE,
  gender CHAR(1),
  phone VARCHAR(15),
  CHECK (gender IN ('m','f','o'))
);

-- ===============================
-- APPOINTMENTS
-- ===============================
CREATE TABLE appointments (
  appointmentid INT AUTO_INCREMENT PRIMARY KEY,
  patientid INT,
  doctorid INT,
  appointmenttime DATETIME,
  status VARCHAR(50),
  FOREIGN KEY (patientid) REFERENCES patients(patientid),
  FOREIGN KEY (doctorid) REFERENCES doctors(doctorid),
  CHECK (status IN ('Scheduled','Completed','Cancelled'))
);

-- ===============================
-- PRESCRIPTIONS
-- ===============================
CREATE TABLE prescriptions (
  prescriptionid INT AUTO_INCREMENT PRIMARY KEY,
  appointmentid INT,
  medication VARCHAR(100),
  dosage VARCHAR(100),
  FOREIGN KEY (appointmentid) REFERENCES appointments(appointmentid)
);

-- ===============================
-- BILLS
-- ===============================
CREATE TABLE bills (
  billid INT AUTO_INCREMENT PRIMARY KEY,
  appointmentid INT,
  amount DECIMAL(10,2),
  paid TINYINT(1),
  billdate DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (appointmentid) REFERENCES appointments(appointmentid)
);

-- ===============================
-- LAB REPORTS
-- ===============================
CREATE TABLE labreports (
  reportid INT AUTO_INCREMENT PRIMARY KEY,
  appointmentid INT,
  reportdata TEXT,
  createdat DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (appointmentid) REFERENCES appointments(appointmentid)
);

-- ===============================
-- INSERT DATA FROM HOSPITAL_DATA
-- ===============================

-- DEPARTMENTS
INSERT INTO departments (departmentid, name)
SELECT DISTINCT
  CAST(NULLIF(TRIM(`Departments.DepartmentID`), '') AS UNSIGNED),
  `Departments.Name`
FROM hospital_data
WHERE TRIM(`Departments.DepartmentID`) <> '';


-- DOCTORS
INSERT INTO doctors (doctorid, name, specialization, role, departmentid)
SELECT
  CAST(NULLIF(TRIM(`Doctors.DoctorID`), '') AS UNSIGNED),
  `Doctors.Name`,
  `Doctors.Specialization`,
  `Doctors.Role`,
  CAST(NULLIF(TRIM(`Doctors.DepartmentID`), '') AS UNSIGNED)
FROM hospital_data
WHERE TRIM(`Doctors.DoctorID`) <> '';


-- PATIENTS
INSERT INTO patients (patientid, name, dateofbirth, gender, phone)
SELECT
  CAST(NULLIF(TRIM(`Patients.PatientID`), '') AS UNSIGNED),
  `Patients.Name`,
  STR_TO_DATE(`Patients.DateOfBirth`, '%d-%m-%Y'),
  LOWER(`Patients.Gender`),
  `Patients.Phone`
FROM hospital_data
WHERE TRIM(`Patients.PatientID`) <> '';


-- APPOINTMENTS
INSERT INTO appointments (appointmentid, patientid, doctorid, appointmenttime, status)
SELECT
  `Appointments.AppointmentID`,
  `Appointments.PatientID`,
  `Appointments.DoctorID`,
  STR_TO_DATE(`Appointments.AppointmentTime`, '%d-%m-%Y %H:%i'),
  `Appointments.Status`
FROM hospital_data;

-- PRESCRIPTIONS
INSERT INTO prescriptions (prescriptionid, appointmentid, medication, dosage)
SELECT
  CAST(NULLIF(TRIM(`Prescriptions.PrescriptionID`), '') AS UNSIGNED),
  CAST(NULLIF(TRIM(`Prescriptions.AppointmentID`), '') AS UNSIGNED),
  `Prescriptions.Medication`,
  `Prescriptions.Dosage`
FROM hospital_data
WHERE TRIM(`Prescriptions.PrescriptionID`) <> '';


-- LAB REPORTS
INSERT INTO labreports (reportid, appointmentid, reportdata, createdat)
SELECT
  CAST(NULLIF(TRIM(`LabReports.ReportID`), '') AS UNSIGNED),
  CAST(NULLIF(TRIM(`LabReports.AppointmentID`), '') AS UNSIGNED),
  `LabReports.ReportData`,
  `LabReports.CreatedAt`
FROM hospital_data
WHERE TRIM(`LabReports.ReportID`) <> '';


-- BILLS
INSERT INTO bills (appointmentid, amount, paid, billdate)
SELECT
  CAST(NULLIF(TRIM(`Bills.AppointmentID`), '') AS UNSIGNED),
  `Bills.Amount`,
  `Bills.Paid`,
  `Bills.BillDate`
FROM hospital_data
WHERE TRIM(`Bills.Amount`) <> '';


-- ===============================
-- TRIGGER: APPOINTMENT VALIDATION
-- ===============================
DROP TRIGGER IF EXISTS check_new_appointment;

DELIMITER $$
DROP TRIGGER IF EXISTS check_new_appointment;

DELIMITER $$

CREATE TRIGGER check_new_appointment
BEFORE INSERT ON appointments
FOR EACH ROW
BEGIN
  IF NEW.appointmenttime < NOW() THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Appointment cannot be in the past';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM appointments
    WHERE doctorid = NEW.doctorid
      AND appointmenttime = NEW.appointmenttime
      AND status = 'Scheduled'
  ) THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Doctor already has an appointment at this time';
  END IF;
END$$

DELIMITER ;


-- ===============================
-- PROCEDURE: VIEW DOCTOR DATA
-- ===============================
DELIMITER $$
CREATE PROCEDURE view_doctor_data (
  IN input_username VARCHAR(100),
  IN input_password VARCHAR(100)
)
BEGIN
  DECLARE doc_role VARCHAR(50);
  DECLARE doc_dept INT;
  DECLARE doc_id INT;

  SELECT doctorid INTO doc_id
  FROM doctor_credentials
  WHERE user_name = input_username
    AND password = input_password;

  SELECT role, departmentid
  INTO doc_role, doc_dept
  FROM doctors
  WHERE doctorid = doc_id;

  IF doc_role = 'senior' THEN
    SELECT d.doctorid, p.patientid, p.name, p.gender,
           a.appointmenttime, pr.medication, lr.reportdata
    FROM appointments a
    JOIN patients p ON a.patientid = p.patientid
    JOIN doctors d ON a.doctorid = d.doctorid
    LEFT JOIN prescriptions pr ON a.appointmentid = pr.appointmentid
    LEFT JOIN labreports lr ON a.appointmentid = lr.appointmentid
    WHERE d.departmentid = doc_dept;
  ELSE
    SELECT a.doctorid, p.patientid, p.name, p.gender,
           a.appointmenttime, pr.medication, lr.reportdata
    FROM appointments a
    JOIN patients p ON a.patientid = p.patientid
    LEFT JOIN prescriptions pr ON a.appointmentid = pr.appointmentid
    LEFT JOIN labreports lr ON a.appointmentid = lr.appointmentid
    WHERE a.doctorid = doc_id;
  END IF;
END$$
DELIMITER ;

-- ===============================
-- PROCEDURE: MONTHLY REVENUE
-- ===============================
DELIMITER //
CREATE PROCEDURE sp_monthlyrevenue (IN p_year INT, IN p_month INT)
BEGIN
  SELECT d1.name AS department,
         SUM(b.amount) AS total_revenue
  FROM bills b
  JOIN appointments a ON b.appointmentid = a.appointmentid
  JOIN doctors d ON a.doctorid = d.doctorid
  JOIN departments d1 ON d.departmentid = d1.departmentid
  WHERE YEAR(b.billdate) = p_year
    AND MONTH(b.billdate) = p_month
  GROUP BY d1.name;
END//
DELIMITER ;
