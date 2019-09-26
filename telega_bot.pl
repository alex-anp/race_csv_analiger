#!/usr/bin/perl

#	Телеграмм робот обработки статистики по вылетам на основании CSV файла от программы Chorus-RF-Laptimer
#	Робот читает сообщения и при наличии в них прикрепленного документа в формате race_YYYYMMDD_XXXXXX.csv, 
#	скачивает его, прогоняет через скрипт plot.py и отправляет результат ответом.  

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

my $BOT_ON = 1; # Для удаленного управления роботом

#########################################################################################
#########################################################################################

# Версия анализатора
my $VER = 'v2';

# Идентификатор робота
my $TOKEN;
my $token_file = './token';

# Параметры для коннекта
my $PROXY = '--socks5-hostname 127.0.0.1:9050';

# Путь к каталогу где будут храниться графики
my $CHARTS_FLD = './charts';

# Путь к каталогу для загрузки CSV файлов
my $CSV_FLD    = './race_csv';

# Путь к каталогу для статистики
my $STAT_FLD   = './race_stat';

# Путь к файлу в котором хранится идентификатор последнего считанного сообщения
my $luid = './last_update_id';

# Путь к файлу в котором хранится настройка диапазона гистограммы
my $gist_range = './gist_range';

# Загружаем текущие значения диапазона гистограммы
my ($left_bound, $right_bound) = get_gist_range();


#########################################################################################

set_token();

while ($BOT_ON) { run(); }

exit;

#########################################################################################

sub run {
	
	my $last_update_id = get_last_update_id();
	
	my $mesages = get_messages($last_update_id);
	
	if ($mesages && ref($mesages) eq 'ARRAY') {
		
		foreach my $msg (@$mesages){
			
			my $chat_id = $msg->{message}->{chat}->{id};
			my $message_id = $msg->{message}->{message_id};
			
			$last_update_id = $msg->{update_id} + 1;
			
			next if -f $CHARTS_FLD.'/race_charts_'.$message_id.'.png';
			
			if (my $doc = $msg->{message}->{document} || $msg->{message}->{reply_to_message}->{document}){
				
				if ($doc->{file_name} && $doc->{file_name} =~ /race_/i && $doc->{file_name} =~ /\.csv/i){
					
					my $file_name = $doc->{file_name};
					
					say $file_name;
					
					get_file($doc->{file_id}, $message_id); 
					
					if ($VER =~ m/v1/){

						say 'Make Charts...';
						make_charts($message_id);

						say 'Send Charts to chat '.$chat_id.'...';
						send_charts($message_id, $chat_id, $file_name);

					} 
					
					if ($VER =~ m/v2/){
						
						say 'Make Charts v2...';
						make_charts_v2($message_id);

						say 'Send Charts v2 to chat '.$chat_id.'...';
						#send_charts_v2($message_id, $chat_id, $file_name);
						
						# Отправляем графиики как альбом изображений
						send_charts_mg($message_id, $chat_id, $file_name);
						
						# Отправляем файл статистики 
						send_stat_file($message_id, $chat_id, $file_name);
					}
						
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
					($left_bound, $right_bound) = get_gist_range();
					send_notify($chat_id, 'Новый диапазон: с '.$left_bound.' по '.$right_bound.' секунду.' );
				}
				
				if ($text =~ m/\/reboot/){
					send_notify($chat_id, 'Пошел на перезагрузку...');
					$BOT_ON = 0;
				}
				
			}
						
		}
		
		set_last_update_id($last_update_id);
		
	}

}

sub get_gist_range {

	if (-f $gist_range){
		
		my $range = `cat $gist_range`;
		
		if ($range =~ m/(\d+)\D+(\d+)/){
			return ($1, $2);
		} else {
			warn 'Wrong range -> "'.$range.'"';	
		}
		
	} else {
		warn "File $gist_range not find!";
	}

	return (10, 40);
}

sub set_gist_range {
	($left_bound, $right_bound) = @_;
	
	my $cmd = "echo '$left_bound $right_bound' > $gist_range";
	
	#warn $cmd;
	
	`$cmd`;
}

sub get_last_update_id {
	
	if (-f $luid){
		return `cat $luid`;
	} else {
		return 0;
	}
	
}

sub set_token {

	if (-f $luid){
		$TOKEN = `cat $token_file`;
		chomp $TOKEN;
	} else {
		die 'ERROR: Invalid Token file ('.$token_file.')';
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

sub make_charts_v2 {
	my $message_id = shift || die 'Nead message_id!!!';
	
	my $csv_file = $CSV_FLD.'/race_data_'.$message_id.'.csv';
	
	my $chart_dir = $CHARTS_FLD.'/race_charts_'.$message_id;
	
	my $cmd = sprintf(
		'/usr/bin/python3 plot_v2.py --hist-left-bound %s --hist-right-bound %s --csv %s --chart-dir %s > %s',
			$left_bound,
			$right_bound,
			$csv_file,
			$chart_dir,
			$STAT_FLD.'/race_stat_'.$message_id.'.txt',
	);
	
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
	
		my $api_link = 'curl '.$PROXY.' -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/sendPhoto -F chat_id="'.$chat_id.'" -F photo="@'.$chart_file.'" -F caption="'.$file_name.'"';
		
		say $api_link;
			
		my $res = `$api_link`;
		
		say $res;
	
	} else {
		
		say 'File not find! - '.$chart_file;
		send_notify($chat_id, 'Не удалось сформировать графики по данным из файла '.$file_name.' :( Вероятние всего, в нем недостаточно статистики.');
		
	}
	
}

sub send_charts_v2 {
	my $message_id = shift || die 'Nead message_id!!!';
	my $chat_id    = shift || die 'Nead chat_id!!!';
	my $file_name  = shift || 'race_data.csv';
	
	my $chart_dir = $CHARTS_FLD.'/race_charts_'.$message_id;
	
	if (-d $chart_dir){
		
		send_notify($chat_id, 'Новые графики (Еще в разработке)');
		
		my @chart_list = split /\s+/, `ls $chart_dir`;
		
		foreach my $chart_file (@chart_list){
			
			next unless $chart_file =~ m/\.png$/i;
			
			my $chart_path = $chart_dir.'/'.$chart_file; 
			
			my $api_link = 'curl '.$PROXY.' -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/sendPhoto -F chat_id="'.$chat_id.'" -F photo="@'.$chart_path.'" -F caption="'.$chart_file.' ('.$file_name.')"';
			
			say $api_link;
				
			my $res = `$api_link`;
			
			say $res;
		
		}
	
	} else {
		
		say 'File not find! - '.$chart_dir;
		send_notify($chat_id, 'Не удалось сформировать графики по данным из файла '.$file_name.' :( Вероятние всего, в нем недостаточно статистики.');
		
	}
	
}

sub send_charts_mg {
	my $message_id = shift || die 'Nead message_id!!!';
	my $chat_id    = shift || die 'Nead chat_id!!!';
	my $file_name  = shift || 'race_data.csv';
	
	my $chart_dir = $CHARTS_FLD.'/race_charts_'.$message_id;
	
	if (-d $chart_dir){
		
		my @chart_list = split /\s+/, `ls $chart_dir`;
		
		my $media_group = [];
		my $attaches = '';
		foreach my $chart_file (@chart_list){
			
			next unless $chart_file =~ m/\.png$/i;
			
			my $chart_path = $chart_dir.'/'.$chart_file; 
			
			$attaches .= sprintf(" -F '%s=@%s'", $chart_file, $chart_path);
			
			push  @$media_group, {
				type => 'photo',
				media => 'attach://'.$chart_file,
				caption => $chart_file.' '.$file_name.'',
			};	
		
		}
	
		my $media_group_json = JSON::XS->new->utf8->encode( $media_group );
		
		my $api_link = sprintf( 
			"curl %s -k -s -X POST https://api.telegram.org/bot%s/sendMediaGroup -F chat_id=%s -F 'media=%s' %s", 
				$PROXY,
				$TOKEN, 
				$chat_id, 
				$media_group_json,
				$attaches,
		);
		
		say $api_link;
			
		my $res = `$api_link`;
		
		say $res;

	
	} else {
		
		say 'File not find! - '.$chart_dir;
		send_notify($chat_id, 'Не удалось сформировать графики по данным из файла '.$file_name.' :( Вероятние всего, в нем недостаточно статистики.');
		
	}
	
}

sub send_stat_file {
	my $message_id = shift || die 'Nead message_id!!!';
	my $chat_id    = shift || die 'Nead chat_id!!!';
	my $file_name  = shift || 'race_data.csv';
	
	my $stat_file = $STAT_FLD.'/race_stat_'.$message_id.'.txt';
	
	if (-e $stat_file){
	
		my $api_link = sprintf(
			"curl %s -k -s -X POST https://api.telegram.org/bot%s/sendDocument -F chat_id=%s -F 'document=@%s' -F 'caption=%s'",
				$PROXY,
				$TOKEN,
				$chat_id,
				$stat_file,
				$file_name
		);
		
		say $api_link;
			
		my $res = `$api_link`;
		
		say $res;
	
	}
	
}

sub get_file {
	my $file_id = shift || return undef;
	my $message_id = shift;
	
	say 'Get File '.$file_id.'...';
	
	my $api_link = 'curl '.$PROXY.' -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/getFile -d file_id='.$file_id.'';
	
	my $res = `$api_link`;
	
	my $data = JSON::XS->new->utf8->decode( $res );
	
	if (my $file = $data->{result}){
		
		my $get_file_link = 'curl '.$PROXY.' -k -s -o "'.$CSV_FLD.'/race_data_'.$message_id.'.csv" https://api.telegram.org/file/bot'.$TOKEN.'/'.$file->{file_path}.'';
		
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
	
	my $api_link = 'curl '.$PROXY.' -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/getUpdates -d timeout=300 -d offset='.$last_update_id.'';
	
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

	my $api_link = 'curl '.$PROXY.' -k -s -X POST https://api.telegram.org/bot'.$TOKEN.'/sendMessage -d chat_id='.$chat_id.' -d text="'.$text.'"';
	`$api_link`;

	say 'To chat:'.$chat_id.' -> '.$text;

		
}

__END__
