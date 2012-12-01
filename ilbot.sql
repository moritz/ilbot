-- MySQL dump 10.11
--
-- Host: localhost    Database: moritz5
-- ------------------------------------------------------
-- Server version	5.0.51a-24+lenny3

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `irclog`
--

DROP TABLE IF EXISTS `irclog`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `irclog` (
  `id` int(11) NOT NULL auto_increment,
  `channel` varchar(30) default NULL,
  `day` char(10) default NULL,
  `nick` varchar(40) default NULL,
  `timestamp` int(11) default NULL,
  `line` mediumtext,
  `spam` tinyint(1) default '0',
  PRIMARY KEY  (`id`),
  KEY `nick_index` (`nick`),
  KEY `day_index` (`day`),
  KEY `irclog_day_channel_idx` (`day`,`channel`),
  KEY `channel_idx` (`channel`),
  FULLTEXT KEY `message_index` (`line`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
SET character_set_client = @saved_cs_client;
