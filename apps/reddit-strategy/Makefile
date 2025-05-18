.PHONY: setup test clean

# Set up development environment
setup:
	python -m pip install -r requirements.txt
	python -m pip install -r requirements-dev.txt

# Run tests with fake Redis
test:
	PYTHONPATH=src python -m pytest -v

# Clean up
clean:
	rm -rf __pycache__ .pytest_cache
	find . -name "*.pyc" -delete
