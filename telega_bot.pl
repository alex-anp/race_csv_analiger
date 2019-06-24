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
my $gist_range = './gist_range';

my ($left_bound, $right_bound) = get_gist_range();


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
			
			$last_update_id = $msg->{update_id} + 1;
			
			next if -f $CHARTS_FLD.'/race_charts_'.$message_id.'.png';
			
			if (my $doc = $msg->{message}->{document} || $msg->{message}->{reply_to_message}->{document}){
				
				if ($doc->{file_name} && $doc->{file_name} =~ /race_/i && $doc->{file_name} =~ /\.csv/i){
					
					my $file_name = $doc->{file_name};
					
					say $file_name;
					
					get_file($doc->{file_id}, $message_id); 
					
					say 'Make Charts...';
						
					make_charts($message_id);
						
					say 'Send Charts to chat '.$chat_id.'...';
					
					send_charts($message_id, $chat_id, $file_name);
						
				} 
				
			}
			
			if (my $text = $msg->{message}->{text}){

				if ($text =~ /help/i){
					send_notify($chat_id, 'Привет! Готов обработать твой race.csv файл, от Chorus-RF-Laptimer. Присылай его, ответом на это сообщение или мне лично, вышлю результат.');
					send_notify($chat_id, '/getrange - Посмотреть диапазон гистограммы. Текущие значения: '.$left_bound.' - '.$right_bound);
					send_notify($chat_id, '/setrange 10 40 - Задать диапазон гистограммы, где 10 40 начальное и конечное значения, диапазона гистограммы.');
				}

				if ($text =~ /getrange/i){
					send_notify($chat_id, 'Текущий диапазон: с '.$left_bound.' по '.$right_bound.' секунду.' );
				}
				
				if ($text =~ /setrange\D+(\d+)\D+(\d+)/i){
					set_gist_range($1,$2);
					send_notify($chat_id, 'Новый диапазон: с '.$left_bound.' по '.$right_bound.' секунду.' );
				}
				
			}
						
		}
		
		set_last_update_id($last_update_id);
		
	}

}

sub get_gist_range {

	if (-f $gist_range){
		
		my $range = `cat $gist_range`;
		
		if ($range =~ m/(\d{2})\D+(\d{2})/){
			
			#say 'Gist range: '.$1.' - '.$2;
			
			return ($1, $2);
		}
		
	}

	return (10, 40);
}

sub set_gist_range {
	($left_bound, $right_bound) = @_;
	
	`echo '$left_bound $right_bound' > $gist_range`;
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
	
	my $cmd = '/usr/bin/python3 plot.py --hist-left-bound '.$left_bound.' --hist-right-bound '.$right_bound.' --csv '.$csv_file.' --chart '.$chart_file.'';
	
	say $cmd;
	
	my $res = `$cmd`;
	
	say $res;
}

sub send_charts {
	my $message_id = shift || die 'Nead message_id!!!';
	my $chat_id    = shift || die 'Nead chat_id!!!';
	my $file_name  = shift || 'race_data.csv';
	
	my $chart_file = $CHARTS_FLD.'/race_charts_'.$message_id.'.png';
	
	if (-e $chart_file){
	
		my $api_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/sendPhoto -F chat_id="'.$chat_id.'" -F photo="@'.$chart_file.'" -F caption="'.$file_name.'"';
		
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
	
	#say 'Get Messages...';
	
	my $api_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/getUpdates -d offset='.$last_update_id.'';
	
	#say $api_link;
	
	my $res = `$api_link`;
	
	
	
	my $data = JSON::XS->new->utf8->decode( $res );
	
	if ($data->{result}){
		return $data->{result};
	} else {
		say $res;
	}
	
	return undef;
	
}

sub send_notify {
	my $chat_id = shift || '-341392670';
	my $text = shift || return undef;

	#if ($TELEGA_ON){
		my $api_link = 'curl --socks5-hostname 127.0.0.1:9050 -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/sendMessage -d chat_id='.$chat_id.' -d text="'.$text.'"';
		`$api_link`;
	#} else {
		say 'To chat:'.$chat_id.' -> '.$text;
	#}
		
}

__END__


