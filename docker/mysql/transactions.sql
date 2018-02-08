

DROP TABLE IF EXISTS `gtr_rep_deleted`;

CREATE TABLE `gtr_rep_deleted` (
  `id` bigint(11) unsigned NOT NULL AUTO_INCREMENT,
  `broker_id` text NOT NULL,
  `entity` text NOT NULL,
  `pk` int(11) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `platform` text NOT NULL,
  `server` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `gtr_idx` (`broker_id`(255),`entity`(255),`platform`(255),`server`(255)),
  KEY `pk_idx` (`pk`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DELIMITER ;;
CREATE PROCEDURE `gtr_rep_handler`(in_broker_id TEXT, in_platform TEXT, in_server TEXT, in_entity TEXT, in_pk INT)
BEGIN

INSERT INTO transactions.gtr_rep_deleted (broker_id, entity, pk, platform, `server`) VALUES (in_broker_id, in_entity, in_pk, in_platform, in_server);

END;;
DELIMITER ;