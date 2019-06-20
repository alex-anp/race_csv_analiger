#!/usr/bin/perl

use strict;
use warnings;
no warnings 'utf8';
use utf8;
use feature 'say';

use Data::Dumper;
use LWP::UserAgent;
use JSON::XS;
use XML::Simple;

my $UA = LWP::UserAgent->new;

#########################################################################################
#########################################################################################

my $TELEGA_ON = 1;
my $TOKEN   = '672698833:AAEHNVa32h9C1qNULClcO2npcARYW8tJTR8';

my $CHARTS_FLD = './charts';
my $CSV_FLD    = './race_csv';

my $luid = './last_update_id';

#########################################################################################

run();

exit;

#########################################################################################

sub run {
	
	my $last_update_id = get_last_update_id();
	
	my $mesages = get_messages($last_update_id);
	
	if ($mesages && ref($mesages) eq 'ARRAY') {
		
		foreach my $msg (@$mesages){
			
			#warn Dumper $msg;
			
			my $chat_id = $msg->{message}->{chat}->{id};
			my $message_id = $msg->{message}->{message_id};
			
			$last_update_id = $msg->{update_id};
			
			next if -f $CHARTS_FLD.'/race_charts_'.$message_id.'.png';
			
			if (my $doc = $msg->{message}->{document}){
				
				if ($doc->{file_name} && $doc->{file_name} =~ /race_/i && $doc->{file_name} =~ /\.csv/i){
					
					say $doc->{file_name};
					
					get_file($doc->{file_id}, $message_id); 
					
					say 'Make Charts...';
						
					make_charts($message_id);
						
					say 'Send Charts to chat '.$chat_id.'...';
					
					send_charts($message_id, $chat_id);
						
				} 
				
			}
						
		}
		
		set_last_update_id($last_update_id);
		
	}

}

sub get_last_update_id {
	
	if (-f $luid){
		return `cat $luid`;
	} else {
		return 0;
	}
	
}

sub set_last_update_id {
	my $last_update_id = shift;
	
	`echo $last_update_id > $luid`;
	
}

sub make_charts {
	my $message_id = shift || die 'Nead message_id!!!';
	
	my $csv_file = $CSV_FLD.'/race_data_'.$message_id.'.csv';
	
	my $chart_file = $CHARTS_FLD.'/race_charts_'.$message_id.'.png';
	
	#python3 plot.py --hist-left-bound 12.0 --hist-right-bound 28 --csv ./race_20190618_010439.csv --only-pilot 'FSN'
	
	my $cmd = '/usr/bin/python3 plot.py --hist-left-bound 12.0 --hist-right-bound 28 --csv '.$csv_file.' --chart '.$chart_file.'';
	
	say $cmd;
	
	my $res = `$cmd`;
	
	say $res;
}

sub send_charts {
	my $message_id = shift || die 'Nead message_id!!!';
	my $chat_id    = shift || die 'Nead chat_id!!!';
	
	my $chart_file = $CHARTS_FLD.'/race_charts_'.$message_id.'.png';
	
	if (-e $chart_file){
	
		my $api_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/sendPhoto -F chat_id="'.$chat_id.'" -F photo="@'.$chart_file.'"';
		
		say $api_link;
			
		my $res = `$api_link`;
		
		say $res;
	
	} else {
		
		say 'File not find! - '.$chart_file;
		
	}
	
}

sub get_file {
	my $file_id = shift || return undef;
	my $message_id = shift;
	
	say 'Get File '.$file_id.'...';
	
	my $api_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/getFile -d file_id='.$file_id.'';
	
	my $res = `$api_link`;
	
	my $data = JSON::XS->new->utf8->decode( $res );
	
	#die Dumper $data;
		
	if (my $file = $data->{result}){
		
		my $get_file_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -o "'.$CSV_FLD.'/race_data_'.$message_id.'.csv" https://api.telegram.org/file/bot'.$TOKEN.'/'.$file->{file_path}.'';
		
		say $get_file_link;
		
		my $res = `$get_file_link`;
		
		return 1;
		
	} 
	
	say $res;	
	
	return undef;
}


sub get_messages {
	my $last_update_id = shift;
	
	say 'Get Messages...';
	
	my $api_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/getUpdates -d offset='.$last_update_id.'';
	
	say $api_link;
	
	my $res = `$api_link`;
	
	
	
	my $data = JSON::XS->new->utf8->decode( $res );
	
	if ($data->{result}){
		return $data->{result};
	}
	
	return undef;
	
}

sub send_notify {
	my $chat_id = shift || '-341392670';
	my $text = shift || return undef;

	
	
	if ($TELEGA_ON){
		
		my $api_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/sendMessage -d chat_id='.$chat_id.' -d text="'.$text.'"';
		
		`$api_link`;
		
	} else {
		
		say $text;
		
	}
		
}

__END__


