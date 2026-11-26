CREATE SCHEMA IF NOT EXISTS lab;

CREATE TABLE IF NOT EXISTS lab.clients (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    sector TEXT,
    contact TEXT
);

CREATE TABLE IF NOT EXISTS lab.robots (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    robot_type TEXT NOT NULL,
    ip_address TEXT,
    status TEXT,
    client_id INTEGER REFERENCES lab.clients(id)
);

CREATE TABLE IF NOT EXISTS lab.robot_credentials (
    id SERIAL PRIMARY KEY,
    robot_type TEXT NOT NULL,
    username TEXT NOT NULL,
    api_key TEXT NOT NULL,
    cert_name TEXT
);

CREATE TABLE IF NOT EXISTS lab.maintenance_jobs (
    id SERIAL PRIMARY KEY,
    robot_id INTEGER REFERENCES lab.robots(id),
    technician TEXT,
    status TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lab.firmware_versions (
    id SERIAL PRIMARY KEY,
    robot_type TEXT NOT NULL,
    version TEXT NOT NULL,
    artifact_url TEXT NOT NULL
);

INSERT INTO lab.clients(name, sector, contact) VALUES
('AutoPlant Alpha', 'Automotive', 'ops@autoplant-alpha.example'),
('PharmaFactory Beta', 'Pharmaceutical', 'it@pharma-beta.example')
ON CONFLICT DO NOTHING;

INSERT INTO lab.robots(name, robot_type, ip_address, status, client_id) VALUES
('robot-a-01', 'A', '10.10.50.101', 'idle', NULL),
('robot-a-02', 'A', '10.10.50.102', 'idle', NULL),
('robot-b-01', 'B', '10.10.50.103', 'idle', NULL),
('client-robot-01', 'A', '10.10.3.10', 'remote', 1),
('client-robot-02', 'B', '10.10.3.11', 'remote', 2)
ON CONFLICT DO NOTHING;

INSERT INTO lab.robot_credentials(robot_type, username, api_key, cert_name) VALUES
('A', 'robot_admin', 'MRX-TYPE-A-SHARED-KEY', 'shared_type_a.pem'),
('B', 'robot_admin', 'MRX-TYPE-B-SHARED-KEY', 'shared_type_b.pem')
ON CONFLICT DO NOTHING;

INSERT INTO lab.firmware_versions(robot_type, version, artifact_url) VALUES
('A', '1.0.0-lab', 'http://artifact-registry/firmware/robot-a-latest.bin'),
('B', '1.0.0-lab', 'http://artifact-registry/firmware/robot-b-latest.bin')
ON CONFLICT DO NOTHING;
