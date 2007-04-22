DROP TABLE IF EXISTS `irclog`;
CREATE TABLE `irclog` (
        channel VARCHAR(30),
        day CHAR(10),
        nick VARCHAR(40),
        timestamp INT,
        line TEXT
        );
