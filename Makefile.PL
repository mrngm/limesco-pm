use 5.012004;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'Net::Limesco',
    VERSION_FROM      => 'lib/Net/Limesco.pm',
    PREREQ_PM         => {
      'Carp'           => 1.17,
      'LWP::UserAgent' => 6.03,
      'JSON'           => 2.53,
    },
    ABSTRACT_FROM  => 'lib/Net/Limesco.pm',
    AUTHOR         => 'Sjors Gielen <sjors@limesco.org>'
);
