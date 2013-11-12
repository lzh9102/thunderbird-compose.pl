Write e-mail in vim and open thunderbird compose window. The e-mail body is
preprocessed using
[Text::Markdown](http://search.cpan.org/~bobtfish/Text-Markdown-1.000031/lib/Text/Markdown.pm)
before being passed to thunderbird.

### Usage

	./thunderbird-compose.pl [-s subject] [-a attachment] [-c cc-list] to-addr ...

### Required perl modules

- Text::Markdown
- HTML::Clean
