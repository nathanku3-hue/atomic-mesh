# Abstract Factory for printing text - OVER ENGINEERED!
from abc import ABC, abstractmethod

class AbstractPrinterFactory(ABC):
    @abstractmethod
    def create_printer(self):
        raise NotImplementedError

class ConcreteConsolePrinter(AbstractPrinterFactory):
    def create_printer(self):
        return self
    
    def print_message(self, msg):
        print(msg)

class TextService:
    def __init__(self, factory):
        self.factory = factory
        self.printer = factory.create_printer()
    
    def execute(self):
        self.printer.print_message("Hello")

# Usage
if __name__ == "__main__":
    TextService(ConcreteConsolePrinter()).execute()
