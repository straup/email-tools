#!/usr/bin/env perl

use strict;

use Getopt::Std;

use Email::Folder;
use Email::Address;
use Email::MIME;

use Date::Parse;
use Date::Format;

use WebService::Solr;

{
    &main();
    exit();
}

sub main {

    my %opts = ();

    getopts('m:e:', \%opts);

    if (! $opts{'e'}){
	$opts{'e'} = 'http://localhost:8983/solr/email-messages';
    }

    my $mbox = Email::Folder->new($opts{'m'});
    my $solr = WebService::Solr->new($opts{'e'});

    my @docs = ();

    foreach my $m ($mbox->messages()){

	my $doc = &message_to_doc($m);
	push @docs, $doc;

	if (scalar(@docs) == 100){
	    $solr->add(\@docs);
	}
    }

    if (scalar(@docs)){
	$solr->add(\@docs);
    }

}

sub message_to_doc($m){
    my $m = shift;

    my $subject = $m->header("Subject");
    my $date = $m->header("Date");
    my $id = $m->header("Message-ID");
    my $reply = $m->header("In-Reply-To");

    $id =~ s/^<//;
    $id =~ s/>$//;
    
    $reply =~ s/^<//;
    $reply =~ s/>$//;

    my $ts = Date::Parse::str2time($date);
    $date = Date::Format::time2str("%Y-%m-%dT%H:%M:%SZ", $ts);
    
    my %doc = (
	'subject' => $subject,
	'date' => $date,
	'message_id' => $id,
	'in_reply_to' => $reply
	);

    my @all_names = ();
    my @all_addresses = ();

    foreach my $h ('To', 'From', 'Cc', 'Bcc'){

	my @addresses = ();

	my $addrs = $m->header($h);

	foreach my $a (Email::Address->parse($addrs)){

	    my $name = $a->name();
	    my $addr = $a->address();

	    eval {
		if (($name) && (! grep(/$name/, @all_names))){
		    push @all_names, $name;
		}
	    };

	    if (! grep(/$addr/, @all_addresses)){
		push @addresses, $addr;
		push @all_addresses, $addr;
	    }
	}

	my $key = "addr_" . lc($h);
	$doc{ $key } = \@addresses;
    }

    $doc{'participants'} = \@all_names;
    $doc{'addr_all'} = \@all_addresses;

    my $e = Email::MIME->new($m->as_string());

    foreach my $p ($e->parts()){

	my $type = $p->content_type;

	if ($type !~ m!text/plain!){
	    next;
	}

	$doc{'body'} = $p->body();
	last;
    }

    return \%doc;
}
