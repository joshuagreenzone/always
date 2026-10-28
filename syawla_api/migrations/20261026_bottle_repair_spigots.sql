-- Physical replacement spigots are separate from the spigot seals consumed on refill.
INSERT INTO inventory_supply (SupplyCode,SupplyName,Category)
VALUES ('SPIGOT_SLIM','Slim bottle spigot','CAP')
ON DUPLICATE KEY UPDATE SupplyCode=VALUES(SupplyCode);
