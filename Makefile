
default:
	./rebar compile

test:
	./rebar compile eunit

clean:
	./rebar clean

PLT_FILE=libs.plt

dialyze: $(PLT_FILE)
	dialyzer --verbose --no_native --apps ebin --plt $(PLT_FILE)

libs.plt:
	dialyzer --build_plt --output_plt $(PLT_FILE) --apps erts kernel stdlib compiler crypto

