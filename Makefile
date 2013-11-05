
default:
	./rebar compile

eunit: default
	./rebar -v eunit

clean:
	./rebar clean

PLT_FILE=libs.plt

dialyze: $(PLT_FILE)
	./rebar compile
	dialyzer --verbose --no_native --apps ebin --plt $(PLT_FILE)

libs.plt:
	dialyzer --build_plt --output_plt $(PLT_FILE) --apps erts kernel stdlib compiler crypto

