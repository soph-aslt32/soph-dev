from typing import Any

HOGE_GLOBAL = 1

class Hoge:
    def __init__(self, name: Any):
        self.name = name

    def greet(self):
        return f"Hello, {self.name}!"

def test_hoge(a: int, b: int):
    assert a >0 and b > 0, "Both a and b should be positive integers."
    hoge = Hoge("Test")
    assert hoge.greet() == "Hello, Test!", "Hoge.greet() should return the correct greeting message."

    x = a + b
    print(f"The sum of {a} and {b} is {x}.")
    return x

if __name__ == "__main__":
    hoge  = Hoge("World")
    print(hoge.greet())
    print("This is a sandbox file for testing code snippets.")

    bracket = ((((((((2))))))))
