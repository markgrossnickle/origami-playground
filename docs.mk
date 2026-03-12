MOONWAVE := moonwave
MOONWAVE_OUTPUT := build

.PHONY: docs docs-serve docs-clean

docs:
	$(MOONWAVE) build --code $(SRC)

docs-serve:
	$(MOONWAVE) dev --code $(SRC)

docs-clean:
	$(RM) -rf $(MOONWAVE_OUTPUT)
