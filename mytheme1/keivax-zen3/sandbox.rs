// ============================================================
// VSCode 配色テーマ確認用 Rust サンプルコード
// ============================================================

use std::collections::HashMap;
use std::fmt;

// --- 定数 ---
const MAX_ITER: usize = 100;
const THRESHOLD: f64 = 1e-9;
const LABEL: &str = "計算結果";

// --- 列挙型 ---
#[derive(Debug, Clone, PartialEq)]
enum Shape {
    Circle(f64),
    Rectangle(f64, f64),
    Triangle { base: f64, height: f64 },
}

// --- 構造体 ---
#[derive(Debug)]
struct Calculator {
    name: String,
    history: Vec<f64>,
    cache: HashMap<String, f64>,
}

// --- トレイト ---
trait Computable {
    fn compute(&self, x: f64) -> f64;
    fn description(&self) -> &str;
}

// --- トレイト実装 ---
impl Computable for Shape {
    fn compute(&self, scale: f64) -> f64 {
        match self {
            Shape::Circle(r) => std::f64::consts::PI * r * r * scale,
            Shape::Rectangle(w, h) => w * h * scale,
            Shape::Triangle { base, height } => 0.5 * base * height * scale,
        }
    }

    fn description(&self) -> &str {
        match self {
            Shape::Circle(_) => "円",
            Shape::Rectangle(_, _) => "長方形",
            Shape::Triangle { .. } => "三角形",
        }
    }
}

// --- Display トレイト ---
impl fmt::Display for Shape {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}(面積={})", self.description(), self.compute(1.0))
    }
}

// --- Calculator 実装 ---
impl Calculator {
    fn new(name: &str) -> Self {
        Calculator {
            name: String::from(name),
            history: Vec::new(),
            cache: HashMap::new(),
        }
    }

    fn factorial(&mut self, n: u64) -> u64 {
        if n <= 1 {
            1
        } else {
            n * self.factorial(n - 1)
        }
    }

    fn fibonacci(&self, n: usize) -> Vec<u64> {
        let mut seq = vec![0u64; n];
        if n >= 1 { seq[0] = 0; }
        if n >= 2 { seq[1] = 1; }
        for i in 2..n {
            seq[i] = seq[i - 1] + seq[i - 2];
        }
        seq
    }

    // 5階層以上のネストを含む関数
    fn deep_nested_calculation(&mut self, data: &[Vec<f64>]) -> Vec<Vec<f64>> {
        let mut results: Vec<Vec<f64>> = Vec::new();

        for (i, row) in data.iter().enumerate() {                      // 階層 1
            let mut row_results: Vec<f64> = Vec::new();
            for (j, &val) in row.iter().enumerate() {                  // 階層 2
                if val > 0.0 {                                         // 階層 3
                    let transformed = match (i + j) % 3 {              // 階層 4
                        0 => {
                            if val < THRESHOLD {                       // 階層 5
                                let tiny = val * 1e6;
                                if tiny.is_finite() {                  // 階層 6
                                    (tiny.sqrt() + 1.0).ln()
                                } else {
                                    0.0
                                }
                            } else {
                                val.sqrt()
                            }
                        }
                        1 => {
                            let base = (val + 1.0).ln();
                            if base > 0.0 {                            // 階層 5
                                for k in 0..3 {                        // 階層 6
                                    if k == (i % 3) {                  // 階層 7
                                        self.history.push(base * (k as f64));
                                    }
                                }
                                base.powi(2)
                            } else {
                                -1.0
                            }
                        }
                        _ => val.sin() * val.cos(),
                    };
                    row_results.push(transformed);
                } else {
                    row_results.push(0.0);
                }
            }
            results.push(row_results);
        }
        results
    }
}

// --- ジェネリック関数 ---
fn find_max<T: PartialOrd + Copy>(slice: &[T]) -> Option<T> {
    slice.iter().copied().reduce(|a, b| if a >= b { a } else { b })
}

fn apply_twice<F: Fn(f64) -> f64>(f: F, x: f64) -> f64 {
    f(f(x))
}

// --- クロージャとイテレータ ---
fn iterator_demo(values: &[f64]) -> (f64, f64, Vec<f64>) {
    let sum: f64 = values.iter().sum();
    let product: f64 = values.iter().fold(1.0, |acc, &x| acc * x);

    let transformed: Vec<f64> = values
        .iter()
        .filter(|&&x| x > 0.0)
        .map(|&x| (x * 2.0).sqrt())
        .enumerate()
        .map(|(i, v)| v + (i as f64) * 0.1)
        .collect();

    (sum, product, transformed)
}

// --- マクロ ---
macro_rules! create_vector {
    ( $( $x:expr ),* ) => {
        {
            let mut temp_vec = Vec::new();
            $(
                temp_vec.push($x);
            )*
            temp_vec
        }
    };
}

macro_rules! log_result {
    ($label:expr, $value:expr) => {
        println!("[{}] {} = {:?}", LABEL, $label, $value);
    };
}

// --- Result / Option 処理 ---
fn safe_divide(a: f64, b: f64) -> Result<f64, String> {
    if b.abs() < THRESHOLD {
        Err(format!("ゼロ除算エラー: {} / {}", a, b))
    } else {
        Ok(a / b)
    }
}

fn chain_operations(x: f64) -> Option<f64> {
    Some(x)
        .filter(|&v| v > 0.0)
        .map(|v| v.sqrt())
        .and_then(|v| if v.is_finite() { Some(v * 2.0) } else { None })
        .map(|v| (v + 1.0).powi(3))
}

// --- ライフタイム ---
fn longest<'a>(s1: &'a str, s2: &'a str) -> &'a str {
    if s1.len() >= s2.len() { s1 } else { s2 }
}

// --- 構造体にライフタイム ---
#[derive(Debug)]
struct Pair<'a, T> {
    first: &'a T,
    second: &'a T,
}

impl<'a, T: fmt::Debug + PartialOrd> Pair<'a, T> {
    fn larger(&self) -> &T {
        if self.first >= self.second { self.first } else { self.second }
    }
}

// --- メイン ---
fn main() {
    // 配列・スライス・かぎかっこ
    let numbers: [i32; 5] = [10, 20, 30, 40, 50];
    let slice: &[i32] = &numbers[1..4];
    let matrix: [[f64; 3]; 3] = [
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0],
        [7.0, 8.0, 9.0],
    ];
    println!("配列: {:?}", numbers);
    println!("スライス: {:?}", slice);
    println!("行列[0][2] = {}", matrix[0][2]);

    // 列挙型
    let shapes = vec![
        Shape::Circle(5.0),
        Shape::Rectangle(3.0, 4.0),
        Shape::Triangle { base: 6.0, height: 3.0 },
    ];
    for s in &shapes {
        println!("{}", s);
    }

    // Calculator
    let mut calc = Calculator::new("メイン計算機");
    log_result!("10!", calc.factorial(10));
    log_result!("fibonacci(10)", calc.fibonacci(10));

    let data = vec![
        vec![1.5, -2.0, 3.7, 0.001],
        vec![4.2, 5.0, -1.0, 8.3],
        vec![0.0, 6.1, 7.4, 2.9],
    ];
    let nested_result = calc.deep_nested_calculation(&data);
    log_result!("ネスト計算", nested_result);

    // ジェネリック
    let max_val = find_max(&[3.14, 2.71, 1.41, 1.73]);
    log_result!("最大値", max_val);

    // クロージャ
    let doubled = apply_twice(|x| x * 2.0, 3.0);
    log_result!("apply_twice(×2, 3)", doubled);

    let square_and_add = |a: f64, b: f64| -> f64 { a.powi(2) + b.powi(2) };
    log_result!("二乗和(3,4)", square_and_add(3.0, 4.0));

    // イテレータ
    let vals = vec![1.0, 2.0, 3.0, 4.0, 5.0];
    let (sum, prod, trans) = iterator_demo(&vals);
    log_result!("合計", sum);
    log_result!("積", prod);
    log_result!("変換後", trans);

    // マクロ
    let macro_vec = create_vector![1, 2, 3, 4, 5];
    log_result!("マクロベクタ", macro_vec);

    // Result / Option
    match safe_divide(10.0, 3.0) {
        Ok(v) => println!("10 / 3 = {:.6}", v),
        Err(e) => eprintln!("エラー: {}", e),
    }

    if let Some(result) = chain_operations(16.0) {
        log_result!("チェーン演算(16)", result);
    }

    // ライフタイム
    let s1 = String::from("Rust");
    let s2 = String::from("プログラミング");
    println!("長い方: {}", longest(&s1, &s2));

    // Pair
    let pair = Pair { first: &42, second: &17 };
    println!("大きい方: {:?}", pair.larger());

    // タプル・パターンマッチ
    let tuples: Vec<(i32, &str, bool)> = vec![
        (1, "alpha", true),
        (2, "beta", false),
        (3, "gamma", true),
    ];
    for &(id, name, active) in &tuples {
        match (id, active) {
            (1, true) => println!("[{}] {} は有効 ✓", id, name),
            (_, false) => println!("[{}] {} は無効 ✗", id, name),
            _ => println!("[{}] {} (その他)", id, name),
        }
    }

    println!("\n=== 完了 ===");
}

// --- テスト ---
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shape_area() {
        let c = Shape::Circle(1.0);
        assert!((c.compute(1.0) - std::f64::consts::PI).abs() < 1e-10);
    }

    #[test]
    fn test_factorial() {
        let mut calc = Calculator::new("test");
        assert_eq!(calc.factorial(5), 120);
        assert_eq!(calc.factorial(0), 1);
    }

    #[test]
    fn test_safe_divide() {
        assert!(safe_divide(1.0, 0.0).is_err());
        assert!((safe_divide(10.0, 4.0).unwrap() - 2.5).abs() < 1e-10);
    }

    #[test]
    fn test_find_max() {
        assert_eq!(find_max(&[1, 5, 3, 2, 4]), Some(5));
        assert_eq!(find_max::<i32>(&[]), None);
    }

    #[test]
    fn test_chain_operations() {
        assert!(chain_operations(-1.0).is_none());
        assert!(chain_operations(4.0).is_some());
    }
}
