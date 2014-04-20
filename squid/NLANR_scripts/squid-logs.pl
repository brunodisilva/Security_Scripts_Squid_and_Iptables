# Subroutines for parsing and analyzing Harvest Cache logs

# squid-logs.pl,v 1.7 1996/06/07 18:43:31 wessels Exp
#
# This file is under RCS control in
#    /O1/Squid_Central/Scripts/RCS/squid-logs.pl,v
#

@cached_WK = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat");
@cached_MO = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
	"Oct", "Nov", "Dec");
%Month = ("Jan", 0, "Feb", 1, "Mar", 2, "Apr", 3, "May", 4, "Jun", 5,
	"Jul", 6, "Aug", 7, "Sep", 8, "Oct", 9, "Nov", 10, "Dec", 11);


sub parse_common_log {
	local($_) = @_;
	local($time,$what,$who,$size,$tag);
	local($ctime,$mday,$mon,$year,$hour,$min,$sec);

	unless (/^(\S+) \S+ \S+ \[([^\]]+)\] "(\w+) ([^"]+)"+ ([\w:]+) (\d+)$/) {

		print STDERR "parse_common_log: Bad input, line $.\n";
		return ();
	}
        $who = $1;
        $ctime = $2;
        $method = $3;
        $what = $4;
        $tag = $5;
        $size = $6;
        $elapsed = "";

        # 02/Nov/1995:23:33:45 -0700
        next unless ($ctime =~ m'(\d+)/(\w+)/(\d+):(\d+):(\d+):(\d+)');
        $mday =  $1;
        $mon = $Month{$2};
        $year = $3 - 1900;
        $hour = $4;
        $min = $5;
        $sec = $6;

        $time = &timelocal($sec,$min,$hour,$mday,$mon,$year);
	return ($time,$elapsed,$who,$tag,$size,$method,$what);
}

# could parse conf/mime.types, but wouldn't get e.g. Applet
%MIME= ("gif","Image", "jpg","Image", "jpeg","Image","xbm","Image",
        "html","HTML","htm","HTML",
        "shtml","SHTML",
        "wrl","VRML",
        "pdf","PDF",
        "map","ISMAP",  # Apache imagemap, if map? or ? not in http_stop
        "ps","PostScript",
        "txt","Text","text","Text","doc","Text",
        "mpg","Movie","mpeg","Movie","avi","Movie","mov","Movie","qt","Movie",
        "au","Audio","wav","Audio","voc","Audio","snd","Audio","aiff","Audio",
        "ram","Audio","gsm","Audio","xdm","Audio","ra","Audio","mp3","Audio",
        "dwg","Drawing",
        "class","Applet",
        "c","Software","f","Software","pl","Software","java","Software",
        "exe","Executable",
        "zip","Bundle","gz","Bundle","z","Bundle","tar","Bundle",
        "hqx","Bundle") ;

sub url_type {
        return 'Directory' if ($what =~ m'/$');
        @F = split ('/', $what);
        $F = pop @F;
        @F = split ('\.', $F);
        $F = pop @F;
        $F =~ tr/A-Z/a-z/;
        $P = pop @F;
        $P =~ tr/A-Z/a-z/;
        $H = pop @F;
        # put xxx.wrl.gz etc. under VRML, not bundle
        if ($H && ($F eq "gz")||($F eq "z")) { $F = $P ; }
        if ($MIME{$F}) { 
          return $MIME{$F} ;
        } else {
          if ($F =~ /\?/) {
            return 'Query' ;        # assuming "?" wasn't in http_stop
          } elsif ($F =~ /=/) {
            return 'Lookup' ;       # probably a redirect of FORM query
          } else {
          #  return $F;
            return 'Other' ;
          }
        }
}

sub commas {
	local($_) = @_;
	1 while s/(.*\d)(\d\d\d)/$1,$2/;
	$_;
}

%FQDN = (
	'132.236.77.25',	'IT',
	'128.182.72.190',	'PB',
	'141.142.121.5',	'UC',
	'192.52.106.30',	'BO',
	'192.203.230.19',	'SV',
	'198.17.46.58',		'SD',
	'198.17.46.59',		'LJ',
	'192.101.98.5',		'DC',
	'204.123.7.1',		'PA'
);

sub fqdn {
        local($dotaddr) = @_;
	local($fqdn, @a);
	return $FQDN{$dotaddr} if defined $FQDN{$dotaddr};
	return ($FQDN{$dotaddr} = $dotaddr)
		unless ($dotaddr =~ /\d+\.\d+\.\d+\.\d+/);
	return 'SV' if ($dotaddr eq '192.203.230.19');
	return 'SV' if ($dotaddr eq '128.102.18.20');	# old
	return 'SD' if ($dotaddr eq '198.17.46.58');
	return 'IT' if ($dotaddr eq '132.236.77.25');
	return 'PB' if ($dotaddr eq '128.182.72.190');
	return 'PB' if ($dotaddr eq '128.182.66.190');	# old
	return 'BO' if ($dotaddr eq '192.52.106.30');
	return 'UC' if ($dotaddr eq '141.142.121.5');
	return 'DC' if ($dotaddr eq '192.101.98.5');
	return 'CH' if ($dotaddr eq '192.172.226.11');
	return 'SF' if ($dotaddr eq '192.172.226.10');
	return 'DC2' if ($dotaddr eq '192.172.226.12');
	return 'NY' if ($dotaddr eq '192.172.226.13');
	return 'old-oceana' if ($dotaddr eq '132.249.229.200');

	$FQDN{$dotaddr} = "[$dotaddr]";
	@a = split('\.', $dotaddr);
	($fqdn) = gethostbyaddr(pack('C4',@a),2);
	$fqdn =~ tr/A-Z/a-z/;
	$FQDN{$dotaddr} = $fqdn unless ($fqdn eq '');
        return $FQDN{$dotaddr};
}


sub percent {
	local($p) = @_;
	return '-' if ($p <= 0);
	sprintf "%d%%", $p * 100 + 0.5;
}

sub center {
	local($_) = @_;
	local($n) = (80 - length) / 2;
	' 'x$n . $_;
}

sub rev_fqdn {
        local($_) = @_;
	$_ = &fqdn($_) if (/^\d+\.\d+\.\d+\.\d+$/);
        return $_ if (/^\[[0-9\.]+\]$/);
        join ('.', reverse split(/\./));
}

%TOP_DOMAINS = (
'ad', 'Andorra',
'ae', 'United Arab Emirates',
'af', 'Afghanistan(Islamic St.)',
'ag', 'Antigua and Barbuda',
'ai', 'Anguilla',
'al', 'Albania',
'am', 'Armenia',
'an', 'Netherland Antilles',
'ao', 'Angola (Republic of)',
'aq', 'Antarctica',
'ar', 'Argentina',
'as', 'American Samoa',
'at', 'Austria',
'au', 'Australia',
'aw', 'Aruba',
'az', 'Azerbaijan',
'ba', 'Bosnia-Herzegovina',
'bb', 'Barbados',
'bd', 'Bangladesh',
'be', 'Belgium',
'bf', 'Burkina Faso',
'bg', 'Bulgaria',
'bh', 'Bahrain',
'bi', 'Burundi',
'bj', 'Benin',
'bm', 'Bermuda',
'bn', 'Brunei Darussalam',
'bo', 'Bolivia',
'br', 'Brazil',
'bs', 'Bahamas',
'bt', 'Bhutan',
'bv', 'Bouvet Island',
'bw', 'Botswana',
'by', 'Belarus',
'bz', 'Belize',
'ca', 'Canada',
'cc', 'Cocos (Keeling) Isl.',
'cf', 'Central African Rep.',
'cg', 'Congo',
'ch', 'Switzerland',
'ci', 'Ivory Coast',
'ck', 'Cook Islands',
'cl', 'Chile',
'cm', 'Cameroon',
'cn', 'China',
'co', 'Colombia',
'cr', 'Costa Rica',
'cs', 'Czechoslovakia',
'cu', 'Cuba',
'cv', 'Cape Verde',
'cx', 'Christmas Island',
'cy', 'Cyprus',
'cz', 'Czech Republic',
'de', 'Germany',
'dj', 'Djibouti',
'dk', 'Denmark',
'dm', 'Dominica',
'do', 'Dominican Republic',
'dz', 'Algeria',
'ec', 'Ecuador',
'ee', 'Estonia',
'eg', 'Egypt',
'eh', 'Western Sahara',
'er', 'Eritrea',
'es', 'Spain',
'et', 'Ethiopia',
'fi', 'Finland',
'fj', 'Fiji',
'fk', 'Falkland Isl.(Malvinas)',
'fm', 'Micronesia',
'fo', 'Faroe Islands',
'fr', 'France',
'fx', 'France (European Ter.)',
'ga', 'Gabon',
'gb', 'Great Britain (UK)',
'gd', 'Grenada',
'ge', 'Georgia',
'gf', 'Guiana (Fr.)',
'gh', 'Ghana',
'gi', 'Gibraltar',
'gl', 'Greenland',
'gm', 'Gambia',
'gn', 'Guinea',
'gp', 'Guadeloupe (Fr.)',
'gq', 'Equatorial Guinea',
'gr', 'Greece',
'gs', 'South Georgia  and',
'gt', 'Guatemala',
'gu', 'Guam (US)',
'gw', 'Guinea Bissau',
'gy', 'Guyana',
'hk', 'Hong Kong',
'hm', 'Heard & McDonald Isl.',
'hn', 'Honduras',
'hr', 'Croatia',
'ht', 'Haiti',
'hu', 'Hungary',
'id', 'Indonesia',
'ie', 'Ireland',
'il', 'Israel',
'in', 'India',
'io', 'British Indian O. Terr.',
'iq', 'Iraq',
'ir', 'Iran',
'is', 'Iceland',
'it', 'Italy',
'jm', 'Jamaica',
'jo', 'Jordan',
'jp', 'Japan',
'ke', 'Kenya',
'kg', 'Kyrgyz Republic',
'kh', 'Cambodia',
'ki', 'Kiribati',
'km', 'Comoros',
'kn', 'St.Kitts Nevis Anguilla',
'kp', 'Korea (North)',
'kr', 'Korea (South)',
'kw', 'Kuwait',
'ky', 'Cayman Islands',
'kz', 'Kazachstan',
'la', 'Laos',
'lb', 'Lebanon',
'lc', 'Saint Lucia',
'li', 'Liechtenstein',
'lk', 'Sri Lanka',
'lr', 'Liberia',
'ls', 'Lesotho',
'lt', 'Lithuania',
'lu', 'Luxembourg',
'lv', 'Latvia',
'ly', 'Libya',
'ma', 'Morocco',
'mc', 'Monaco',
'md', 'Moldova',
'mg', 'Madagascar (Republic of)',
'mh', 'Marshall Islands',
'mk', 'Macedonia (former Yug.)',
'ml', 'Mali',
'mm', 'Myanmar',
'mn', 'Mongolia',
'mo', 'Macau',
'mp', 'Northern Mariana Isl.',
'mq', 'Martinique (Fr.)',
'mr', 'Mauritania',
'ms', 'Montserrat',
'mt', 'Malta',
'mu', 'Mauritius',
'mv', 'Maldives',
'mw', 'Malawi',
'mx', 'Mexico',
'my', 'Malaysia',
'mz', 'Mozambique',
'na', 'Namibia',
'nc', 'New Caledonia (Fr.)',
'ne', 'Niger',
'nf', 'Norfolk Island',
'ng', 'Nigeria',
'ni', 'Nicaragua',
'nl', 'Netherlands',
'no', 'Norway',
'np', 'Nepal',
'nr', 'Nauru',
'nu', 'Niue',
'nz', 'New Zealand',
'om', 'Oman',
'pa', 'Panama',
'pe', 'Peru',
'pf', 'Polynesia (Fr.)',
'pg', 'Papua New Guinea',
'ph', 'Philippines',
'pk', 'Pakistan',
'pl', 'Poland',
'pm', 'St. Pierre & Miquelon',
'pn', 'Pitcairn',
'pr', 'Puerto Rico (US)',
'pt', 'Portugal',
'pw', 'Palau',
'py', 'Paraguay',
'qa', 'Qatar',
're', 'Reunion (Fr.)',
'ro', 'Romania',
'ru', 'Russian',
'rw', 'Rwanda',
'sa', 'Saudi Arabia',
'sb', 'Solomon Islands',
'sc', 'Seychelles',
'sd', 'Sudan',
'se', 'Sweden',
'sg', 'Singapore',
'sh', 'St. Helena',
'si', 'Slovenia',
'sj', 'Svalbard & Jan Mayen Is',
'sk', 'Slovakia (Slovak Rep)',
'sl', 'Sierra Leone',
'sm', 'San Marino',
'sn', 'Senegal',
'so', 'Somalia',
'sr', 'Suriname',
'st', 'St. Tome and Principe',
'su', 'Soviet Union',
'sv', 'El Salvador',
'sy', 'Syria',
'sz', 'Swaziland',
'tc', 'Turks & Caicos Islands',
'td', 'Chad',
'tf', 'French Southern Terr.',
'tg', 'Togo',
'th', 'Thailand',
'tj', 'Tadjikistan',
'tk', 'Tokelau',
'tm', 'Turkmenistan',
'tn', 'Tunisia',
'to', 'Tonga',
'tp', 'East Timor',
'tr', 'Turkey',
'tt', 'Trinidad and Tobago',
'tv', 'Tuvalu',
'tw', 'Taiwan',
'tz', 'Tanzania',
'ua', 'Ukraine',
'ug', 'Uganda',
'uk', 'United Kingdom',
'um', 'US Minor outlying Isl.',
'us', 'United States',
'uy', 'Uruguay',
'uz', 'Uzbekistan',
'va', 'Vatican City State',
'vc', 'St.Vincent and Grenadines',
've', 'Venezuela',
'vg', 'Virgin Islands (British)',
'vi', 'Virgin Islands (US)',
'vn', 'Vietnam',
'vu', 'Vanuatu',
'wf', 'Wallis and Futuna Islands',
'ws', 'Samoa',
'ye', 'Yemen',
'yt', 'Mayotte',
'yu', 'Yugoslavia',
'za', 'South Africa',
'zm', 'Zambia',
'zr', 'Zaire',
'zw', 'Zimbabwe',
'arpa', 'Old style Arpanet',
'com', 'Commercial',
'edu', 'Educational',
'gov', 'Government',
'int', 'International field',
'mil', 'US Military',
'nato', 'Nato field',
'net', 'Network',
'org',  'Non-Profit Organization'
);

sub top_level_domain {
	local($_) = @_;
        local(@F) = split(/\./);
        local($dom) = pop @F;
	return $dom if defined $TOP_DOMAINS{$dom};
	return  'Unknown';
}

sub top_domain_name {
	local($_) = @_;
	return 'Unknown' unless defined $TOP_DOMAINS{$_};
	$_ . ' ' . $TOP_DOMAINS{$_};
}

sub strtime {
        local ($t) = shift;
        @lt = localtime ($t);
        sprintf ("%s %s %2d %02d:%02d:%02d %d",
                $cached_WK[$lt[6]], $cached_MO[$lt[4]], $lt[3],
                $lt[2], $lt[1], $lt[0],
                1900+$lt[5]);
}

sub ipaddr {
        local($name) = @_;
        ($name,$alias,$type,$len,$addr) = gethostbyname($name);
        @ip = unpack('C4', $addr);
        return join ('.', @ip);
}

1;

