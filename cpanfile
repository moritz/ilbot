
requires 'Bot::BasicBot';
requires 'Calendar::Simple'
requires 'Config::File';
requires 'CGI';
requires 'Date::Simple';
requires 'DBI';
requires 'CGI::Carp';
requires 'Encode::Guess';
requires 'HTML::Entities';
requires 'HTML::Template';
requires 'HTTP::Headers';
requires 'File::Slurp';
requires 'Regexp::Common';
requires 'Text::Table';
requires 'Cache::Cache';
requires 'DBD::mysql';

recommends 'JSON::XS', '2.0';
conflicts 'JSON', '< 1.0';
