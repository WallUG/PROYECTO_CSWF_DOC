-- ================================================
-- MIGRACIÓN A MYSQL - SISTEMA DE GESTIÓN DE TALLER
-- ================================================

-- 1. LIMPIEZA DE TABLAS ANTERIORES
DROP TABLE IF EXISTS detalle_orden;
DROP TABLE IF EXISTS orden_servicio;
DROP TABLE IF EXISTS item_catalogo;
DROP TABLE IF EXISTS vehiculo;
DROP TABLE IF EXISTS tecnico;
DROP TABLE IF EXISTS usuario;
DROP TABLE IF EXISTS cliente;

-- =========================
-- TABLA: CLIENTE
-- =========================
CREATE TABLE cliente (
    id_cliente   INT AUTO_INCREMENT PRIMARY KEY,
    cedula       VARCHAR(20) UNIQUE NOT NULL,
    nombres      VARCHAR(150) NOT NULL,
    telefono     VARCHAR(30),
    direccion    VARCHAR(200),
    email        VARCHAR(150),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- =========================
-- TABLA: USUARIO
-- =========================
CREATE TABLE usuario (
    id_usuario    INT AUTO_INCREMENT PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL,
    correo        VARCHAR(150) UNIQUE NOT NULL,
    password      VARCHAR(200) NOT NULL,
    rol           VARCHAR(20) NOT NULL,
    estado_cuenta BOOLEAN DEFAULT TRUE,
    id_cliente    INT NULL, 
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_rol CHECK (rol IN ('Admin', 'Tecnico', 'Cliente')),
    CONSTRAINT fk_usuario_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE SET NULL
);

-- =========================
-- TABLA: TECNICO
-- =========================
CREATE TABLE tecnico (
    id_usuario            INT PRIMARY KEY,
    especialidad          VARCHAR(100),
    estado_disponibilidad VARCHAR(50) DEFAULT 'Disponible',
    created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_estado_tec CHECK (estado_disponibilidad IN ('Disponible', 'Ocupado', 'No Disponible')),
    CONSTRAINT fk_tecnico_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE
);

-- =========================
-- TABLA: VEHICULO
-- =========================
CREATE TABLE vehiculo (
    id_vehiculo  INT AUTO_INCREMENT PRIMARY KEY,
    placa        VARCHAR(20) UNIQUE NOT NULL,
    marca        VARCHAR(50) NOT NULL,
    modelo       VARCHAR(50) NOT NULL,
    anio         INT,
    color        VARCHAR(30),
    kilometraje  INT DEFAULT 0,
    id_cliente   INT NOT NULL,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_vehiculo_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE CASCADE
);

-- =========================
-- TABLA: ITEM_CATALOGO 
-- =========================
CREATE TABLE item_catalogo (
    id_item      INT AUTO_INCREMENT PRIMARY KEY,
    codigo       VARCHAR(30) UNIQUE NOT NULL,
    nombre       VARCHAR(150) NOT NULL,
    tipo         VARCHAR(20) NOT NULL,
    descripcion  VARCHAR(300),
    precio_base  DECIMAL(10,2) NOT NULL,
    stock        INT DEFAULT 0,
    stock_minimo INT DEFAULT 5,
    activo       BOOLEAN DEFAULT TRUE,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_tipo_item CHECK (tipo IN ('Repuesto', 'ManoObra'))
);

-- =========================
-- TABLA: ORDEN_SERVICIO
-- =========================
CREATE TABLE orden_servicio (
    id_orden            INT AUTO_INCREMENT PRIMARY KEY,
    numero_orden        VARCHAR(30) UNIQUE NOT NULL, 
    fecha_ingreso       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_entrega       TIMESTAMP NULL,
    motivo_ingreso      VARCHAR(500),
    diagnostico_tecnico VARCHAR(1000),
    estado              VARCHAR(30) DEFAULT 'Pendiente',
    total_estimado      DECIMAL(10,2) NOT NULL DEFAULT 0,
    id_vehiculo         INT NOT NULL,
    id_tecnico          INT NOT NULL,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_estado_orden CHECK (estado IN ('Pendiente', 'En Proceso', 'En Espera de Repuestos', 'Finalizado', 'Entregado', 'Cancelado')),
    CONSTRAINT fk_orden_vehiculo FOREIGN KEY (id_vehiculo) REFERENCES vehiculo(id_vehiculo) ON DELETE RESTRICT,
    CONSTRAINT fk_orden_tecnico FOREIGN KEY (id_tecnico) REFERENCES tecnico(id_usuario) ON DELETE RESTRICT
);

-- =========================
-- TABLA: DETALLE_ORDEN
-- =========================
CREATE TABLE detalle_orden (
    id_detalle       INT AUTO_INCREMENT PRIMARY KEY,
    id_orden         INT NOT NULL,
    id_item          INT NOT NULL,
    cantidad         INT NOT NULL,
    precio_unitario  DECIMAL(10,2) NOT NULL,
    subtotal         DECIMAL(10,2) NOT NULL DEFAULT 0, -- ¡CORRECCIÓN APLICADA AQUÍ!
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_cantidad CHECK (cantidad > 0),
    CONSTRAINT fk_detalle_orden FOREIGN KEY (id_orden) REFERENCES orden_servicio(id_orden) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_item FOREIGN KEY (id_item) REFERENCES item_catalogo(id_item) ON DELETE RESTRICT
);

-- ================================================
-- ÍNDICES PARA OPTIMIZACIÓN
-- ================================================
CREATE INDEX idx_usuario_correo ON usuario(correo);
CREATE INDEX idx_cliente_cedula ON cliente(cedula);
CREATE INDEX idx_vehiculo_placa ON vehiculo(placa);
CREATE INDEX idx_vehiculo_cliente ON vehiculo(id_cliente);
CREATE INDEX idx_orden_estado ON orden_servicio(estado);

-- ================================================
-- TRIGGERS MAESTROS
-- ================================================
DELIMITER //

-- 1. TRIGGERS ANTES DE INSERTAR/ACTUALIZAR (Calculan el subtotal de la fila)
CREATE TRIGGER trg_before_insert_detalle BEFORE INSERT ON detalle_orden
FOR EACH ROW BEGIN
    SET NEW.subtotal = NEW.cantidad * NEW.precio_unitario;
END //

CREATE TRIGGER trg_before_update_detalle BEFORE UPDATE ON detalle_orden
FOR EACH ROW BEGIN
    SET NEW.subtotal = NEW.cantidad * NEW.precio_unitario;
END //

-- 2. TRIGGERS DESPUÉS DE LA ACCIÓN (Suman el total de la orden y actualizan inventario)
CREATE TRIGGER trg_after_insert_detalle AFTER INSERT ON detalle_orden
FOR EACH ROW BEGIN
    -- A) Actualizar costo de la orden
    UPDATE orden_servicio SET total_estimado = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_orden WHERE id_orden = NEW.id_orden) WHERE id_orden = NEW.id_orden;
    -- B) Descontar stock (solo si es repuesto)
    UPDATE item_catalogo SET stock = stock - NEW.cantidad WHERE id_item = NEW.id_item AND tipo = 'Repuesto';
END //

CREATE TRIGGER trg_after_update_detalle AFTER UPDATE ON detalle_orden
FOR EACH ROW BEGIN
    -- A) Actualizar costo de la orden
    UPDATE orden_servicio SET total_estimado = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_orden WHERE id_orden = NEW.id_orden) WHERE id_orden = NEW.id_orden;
    -- B) Ajustar stock (Se devuelve la cantidad anterior y se resta la nueva)
    UPDATE item_catalogo SET stock = stock + OLD.cantidad WHERE id_item = OLD.id_item AND tipo = 'Repuesto';
    UPDATE item_catalogo SET stock = stock - NEW.cantidad WHERE id_item = NEW.id_item AND tipo = 'Repuesto';
END //

CREATE TRIGGER trg_after_delete_detalle AFTER DELETE ON detalle_orden
FOR EACH ROW BEGIN
    -- A) Actualizar costo de la orden
    UPDATE orden_servicio SET total_estimado = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_orden WHERE id_orden = OLD.id_orden) WHERE id_orden = OLD.id_orden;
    -- B) Devolver stock al inventario
    UPDATE item_catalogo SET stock = stock + OLD.cantidad WHERE id_item = OLD.id_item AND tipo = 'Repuesto';
END //

DELIMITER ;


-- ================================================
-- INSERCIÓN DE DATOS DE PRUEBA
-- ================================================
INSERT INTO cliente (cedula, nombres) VALUES ('1234567890', 'Pedro González');
INSERT INTO usuario (nombre, correo, password, rol) VALUES ('Carlos', 'admin@taller.com', 'hash', 'Admin'), ('Juan', 'tecnico@taller.com', 'hash', 'Tecnico');
INSERT INTO tecnico (id_usuario, especialidad) VALUES (2, 'Mecánica General');
INSERT INTO vehiculo (placa, marca, modelo, id_cliente) VALUES ('ABC-1234', 'Toyota', 'Corolla', 1);

-- Nota: Iniciamos con 50 filtros de aceite.
INSERT INTO item_catalogo (codigo, nombre, tipo, precio_base, stock) VALUES 
('REP-001', 'Filtro de aceite', 'Repuesto', 15.00, 50),
('MO-001', 'Cambio de aceite', 'ManoObra', 20.00, 999);

INSERT INTO orden_servicio (numero_orden, estado, id_vehiculo, id_tecnico) VALUES ('ORD-20260509-001', 'En Proceso', 1, 2);

-- ¡Y AHORA SÍ! Al insertar esto, no dará error. El total se actualizará a $35 y el stock del filtro bajará a 49.
INSERT INTO detalle_orden (id_orden, id_item, cantidad, precio_unitario) VALUES 
(1, 1, 1, 15.00), 
(1, 2, 1, 20.00);
