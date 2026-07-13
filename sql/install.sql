CREATE TABLE IF NOT EXISTS `esx_invoices` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `ref_id` VARCHAR(10) NOT NULL,
  `group_id` VARCHAR(40) DEFAULT NULL,
  `receiver_identifier` VARCHAR(60) NOT NULL,
  `receiver_name` VARCHAR(100) NOT NULL,
  `author_identifier` VARCHAR(60) NOT NULL,
  `author_name` VARCHAR(100) NOT NULL,
  `society` VARCHAR(50) DEFAULT NULL,
  `society_label` VARCHAR(100) DEFAULT NULL,
  `item` VARCHAR(150) NOT NULL,
  `invoice_value` INT(11) NOT NULL,
  `original_value` INT(11) DEFAULT NULL,
  `insurance_covered` INT(11) NOT NULL DEFAULT 0,
  `fee_amount` INT(11) NOT NULL DEFAULT 0,
  `commission_amount` INT(11) NOT NULL DEFAULT 0,
  `is_installment` TINYINT(1) NOT NULL DEFAULT 0,
  `installment_count` INT(11) DEFAULT NULL,
  `status` ENUM('open','paid','autopaid','cancelled') NOT NULL DEFAULT 'open',
  `notes` VARCHAR(255) DEFAULT NULL,
  `sent_date` DATETIME NOT NULL,
  `limit_pay_date` DATETIME NOT NULL,
  `paid_date` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_ref_id` (`ref_id`),
  INDEX `idx_receiver` (`receiver_identifier`),
  INDEX `idx_author` (`author_identifier`),
  INDEX `idx_status` (`status`),
  INDEX `idx_group` (`group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Einzelpositionen einer Rechnung (mehrere Positionen pro Rechnung)
CREATE TABLE IF NOT EXISTS `esx_invoice_items` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `invoice_id` INT(11) NOT NULL,
  `label` VARCHAR(150) NOT NULL,
  `price` INT(11) NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_invoice` (`invoice_id`),
  CONSTRAINT `fk_items_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `esx_invoices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Raten einer Ratenzahlungs-Rechnung
CREATE TABLE IF NOT EXISTS `esx_invoice_installments` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `invoice_id` INT(11) NOT NULL,
  `part_number` INT(11) NOT NULL,
  `amount` INT(11) NOT NULL,
  `status` ENUM('open','paid') NOT NULL DEFAULT 'open',
  `due_date` DATETIME NOT NULL,
  `paid_date` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_invoice` (`invoice_id`),
  CONSTRAINT `fk_installments_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `esx_invoices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
