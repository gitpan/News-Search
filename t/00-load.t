#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'News::Search' );
}

diag( "Testing News::Search $News::Search::VERSION, Perl $], $^X" );
