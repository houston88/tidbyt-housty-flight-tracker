-include .env
export

SCRIPT = texins_flights.star
OUTPUT = texins_flights.webp

.PHONY: render serve demo cycle push push-bg

INSTALLATION_ID ?= texins-flights

render:
	pixlet render $(SCRIPT) api_key="$(FLIGHTAWARE_API_KEY)" -o $(OUTPUT)

serve:
	pixlet serve $(SCRIPT)

demo:
	pixlet render $(SCRIPT) mode=demo --gif -m 8 -o preview_airborne.gif

cycle:
	pixlet render $(SCRIPT) api_key="$(FLIGHTAWARE_API_KEY)" mode=cycle --gif -m 8 -o preview_cycle.gif

push: render
	@if [ -z "$(TIDBYT_DEVICE_ID)" ] || [ -z "$(TIDBYT_API_KEY)" ]; then \
		echo "Error: TIDBYT_DEVICE_ID and TIDBYT_API_KEY must be set in .env or passed as environment variables."; \
		exit 1; \
	fi
	pixlet push $(TIDBYT_DEVICE_ID) $(OUTPUT) -t $(TIDBYT_API_KEY) -i $(INSTALLATION_ID)

push-bg: render
	@if [ -z "$(TIDBYT_DEVICE_ID)" ] || [ -z "$(TIDBYT_API_KEY)" ]; then \
		echo "Error: TIDBYT_DEVICE_ID and TIDBYT_API_KEY must be set in .env or passed as environment variables."; \
		exit 1; \
	fi
	pixlet push $(TIDBYT_DEVICE_ID) $(OUTPUT) -t $(TIDBYT_API_KEY) -i $(INSTALLATION_ID) -b

