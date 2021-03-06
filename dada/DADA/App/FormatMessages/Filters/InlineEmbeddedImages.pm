package DADA::App::FormatMessages::Filters::InlineEmbeddedImages;
use strict; 

use lib qw(
	../../../../
	../../../../DADA/perllib
); 

use vars qw($AUTOLOAD); 
use DADA::Config qw(!:DEFAULT);

use Carp qw(croak carp); 
use HTML::LinkExtor; 
use URI::file; 
use URI; 

# Need to ship with: 
use File::Slurp;
use DADA::Security::Password; 
use DADA::App::Guts; 
use Data::Dumper; 

use MIME::Parser; 
use MIME::Entity; 

my $parser                    = new MIME::Parser;
   $parser                    = optimize_mime_parser($parser);
my $files_that_need_attaching = [];

my $t = 0; 

my %allowed = (

);

sub new {

	my $that = shift; 
	my $class = ref($that) || $that; 
	
	my $self = {
		_permitted => \%allowed, 
		%allowed,
	};
	
	bless $self, $class;
	
	my $args = (@_); 
    
   $self->_init($args); 
   return $self;

}




sub AUTOLOAD { 
    my $self = shift; 
    my $type = ref($self) 
    	or croak "$self is not an object"; 
    	
    my $name = $AUTOLOAD;
       $name =~ s/.*://; #strip fully qualifies portion 
    
    unless (exists  $self -> {_permitted} -> {$name}) { 
    	croak "Can't access '$name' field in object of class $type"; 
    }    
    if(@_) { 
        return $self->{$name} = shift; 
    } else { 
        return $self->{$name}; 
    }
}





sub _init  {

	my $self    = shift; 
	my ($args)  = @_;
	
}


sub filter { 
	my $self   = shift; 
	my ($args) = @_; 
	if(exists($args->{-raw_msg})){ 
		my $entity = $parser->parse_data($args->{-raw_msg});
		   $entity = $self->switch_inline({-entity => $entity}); 
		return $entity; 
	}
	elsif(exists($args->{-html_msg})){ 
		my $html = $self->switcheroo($args->{-html_msg}); 
		return $html; 
	}
	else { 
		carp "I'm not sure what you want me to do!"; 
		return undef; 
	}
}

sub switch_inline { 
	my $self   = shift; 
	my ($args) = @_;
	my $entity = scan_and_parse($args); 
	# $entity = $self->attach_files({-entity => $entity}); 
	return $entity; 
}
sub scan_and_parse {
	my $self   = shift; 
    my ($args) = @_;
    my @parts = $args->{-entity}->parts;
    if ( !exists( $args->{-entity} ) ) {
        croak 'did not pass an entity in, "-entity"!';
    }

    my @parts = $args->{-entity}->parts;

    if (@parts) {
        warn "this part has " . $#parts . "parts."
          if $t;

        my $i;
        for $i ( 0 .. $#parts ) {
            $parts[$i] = scan_and_parse( { %{$args}, -entity => $parts[$i] } );
        }

        $args->{-entity}->sync_headers(
            'Length'      => 'ERASE',
            'Nonstandard' => 'ERASE'
        );

    }
    else {

        my $is_att = 0;
        if (
            defined( $args->{-entity}->head->mime_attr('content-disposition') )
          )
        {
            warn q{content-disposition has set to: }
              . $args->{-entity}->head->mime_attr('content-disposition')
              if $t;
            if ( $args->{-entity}->head->mime_attr('content-disposition') =~
                m/attachment/ )
            {
                warn "we have an attachment?"
                  if $t;
                $is_att = 1;
            }
        }
        else {
            warn "can't find a content-disposition"
              if $t;
        }

        if (
            (
                  ( $args->{-entity}->head->mime_type eq 'text/html' )
            )
            && ( $is_att != 1 )
          )
        {

            warn 'html, non-attachment part'
              if $t;

            my $body    = $args->{-entity}->bodyhandle;
            my $content = $args->{-entity}->bodyhandle->as_string;
            $content = safely_decode($content);
            $content = $self->switcheroo($content);

            my $io = $body->open('w');
            $content = safely_encode($content);
            $io->print($content);
            $io->close;
        }

        $args->{-entity}->sync_headers(

            #'Length'      => 'COMPUTE', #optimization
            'Length'      => 'ERASE',
            'Nonstandard' => 'ERASE'
        );
    }
    return $args->{-entity};

}


sub switcheroo { 
	my $self   = shift; 
	my $msg = shift; 
	 sub find_img {
	     my($tag, %attr) = @_;
	     return if $tag ne 'img';  # we only look closer at <a ...>
		 my $src =  $attr{src}; 
		#print '$src: ' . $src;
		if($src =~ m/^data/){ 
			my $uri = URI->new($src);
			my $type;
			$src =~ m/^data\:(.*?)\;base64/;
			$type = $1;
			my $filename = ''; 
						
			my $mime_types = { 
				'image/jpeg' => 'jpg', 
				'image/jpg'  => 'jpg', 
				'image/png'  => 'png', 
				'image/gif'  => 'gif', 
			};
			
			if(! exists($mime_types->{$type})){ 
				carp "Skipping image - unknown mime-type! '$type'"; 
				return ;
			}
			else { 
				$filename = DADA::Security::Password::generate_rand_string() . '-' . $self->time_stamp . '-inline.' . $mime_types->{$type}; 
			}
			
			my $img_dir   = make_safer($DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_dir} . '/images/');  
			my $full_path = make_safer($img_dir . '/' . $filename); 
			
			if(! -d $img_dir){ 
				mkdir($img_dir, $DADA::Config::DIR_CHMOD); 
			}
			
			if(-e $full_path) { 
				carp "Filename already exists! at: $full_path"; 
			}
			else { 
				open my $img, '>', $full_path or die $!; 
			 	print $img $uri->data();  
				close $img; 
				
				my $search_src = quotemeta($src);
				# $msg =~ s/$search_src/cid\:$filename/; 
				my $full_url = $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_url} . '/images/' . $filename; 
				$msg =~ s/$search_src/$full_url/; 
				push(@$files_that_need_attaching, $filename); 
			}
		}
	}
	
	my $p = HTML::LinkExtor->new(\&find_img);
	$p->parse($msg); 
	return $msg; 
}


sub attach_files {
	my $self = shift; 
    my ($args) = @_;
    my $entity = $args->{-entity};

   for my $file (@$files_that_need_attaching) {
        print "file: $file\n"; 
		my $attach = MIME::Entity->build(
            Type          => "image/jpeg",
            Encoding      => "base64",
            Path          => $file,
            Filename      => $file,
            Disposition   => "attachment",
			Id            => $file, 
        );
		$entity->add_part($attach); 
    }
	# $entity->dump_skeleton(\*STDERR);
    
    return $entity;
}

sub time_stamp { 
	my $self = shift; 
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $timestamp = sprintf("%4d-%02d-%02d", $year+1900,$mon+1,$mday) . '-'; # . time;
	return $timestamp; 
}

1;
