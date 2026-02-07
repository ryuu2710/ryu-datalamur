

## The Architect's Approach

Để giải quyết bài này, chúng ta phải chuyển dịch tư duy từ lọc từng dòng sang lọc theo **Nhóm**. Chúng ta cần dùng kỹ thuật gọi là **Relational Division**.

### Solution: Pattern "Filtering by Aggregation"

```sql
SELECT candidate_id
FROM candidates
WHERE skill IN ('Python', 'Tableau', 'PostgreSQL') -- Bước 1: Thu hẹp phạm vi
GROUP BY candidate_id                             -- Bước 2: Gom nhóm theo từng người
HAVING COUNT(DISTINCT skill) = 3;                 -- Bước 3: Kiểm tra điều kiện "đủ bộ"

```

### Tại sao cách này hoạt động?

1. **WHERE IN**: Chúng ta lấy ra tất cả các dòng thuộc về 1 trong 3 kỹ năng đó.
2. **GROUP BY**: Chúng ta gom tất cả các dòng của cùng một ứng viên lại vào một "cái xô" (bucket).
3. **HAVING**: Đây là "WHERE dành cho nhóm". Chúng ta đếm xem trong "cái xô" của ứng viên đó có bao nhiêu kỹ năng **duy nhất**. Nếu bằng 3, nghĩa là ứng viên đó sở hữu trọn bộ combo bạn cần.

---

## 4. Bài học khắc cốt ghi tâm (DDIA Mindset)

* **Lesson 1: WHERE vs. HAVING.** `WHERE` dùng để lọc dữ liệu thô trước khi tính toán. `HAVING` dùng để lọc kết quả sau khi đã gom nhóm.
* **Lesson 2: Data Modeling Trade-offs (Chapter 4).** Nếu bạn thấy mình thường xuyên phải viết những query phức tạp này chỉ để tìm kỹ năng, có lẽ thiết kế bảng theo dạng "Narrow Table" (mỗi kỹ năng một dòng) đang làm khó bạn.
* **Trade-off:** Thiết kế này giúp thêm kỹ năng mới linh hoạt (vô hạn), nhưng lại khiến các câu truy vấn "AND" trở nên đắt đỏ vì phải thực hiện `GROUP BY` và `COUNT`.
* **Alternative:** Nếu dùng Document DB (như MongoDB - Chapter 2), bạn có thể lưu `skills` thành một mảng `['Python', 'Tableau', 'Postgres']` trong một Document duy nhất. Khi đó, query sẽ đơn giản hơn nhưng việc index trên mảng lại phức tạp theo kiểu khác.



---

### Mentor's Socratic Question:

> "Nếu bảng `candidates` của bạn có 1 tỷ dòng và mỗi ứng viên có hàng trăm kỹ năng, việc dùng `GROUP BY` và `COUNT(DISTINCT)` sẽ cực kỳ chậm do tốn tài nguyên CPU và RAM để băm (hash) các nhóm. Bạn có thể dùng phép **JOIN (Self-join)** để giải bài này không? Và theo bạn, giữa **JOIN** 3 lần và **GROUP BY**, cái nào sẽ gây áp lực lớn hơn lên bộ nhớ (Memory) của Database?"

#### Câu trả lời
Đây là một câu hỏi rất sâu về mặt **vận hành hệ thống (System Internals)**. Để giải thích cho bạn, chúng ta sẽ lật mở "nắp máy" của Database Engine dựa trên các nguyên lý trong **Chương 3 (Storage and Retrieval)** của cuốn DDIA.


### 1. Tại sao `GROUP BY` + `COUNT(DISTINCT)` lại tốn RAM/CPU khi dữ liệu lớn?

Khi bạn thực hiện `GROUP BY candidate_id`, Database thường sử dụng một trong hai chiến lược (theo **Chapter 3**):

* **Hash Aggregation:** Database tạo một **Hash Table** trong RAM. Key là `candidate_id`, và Value là một tập hợp (Set) các kỹ năng để đếm `DISTINCT`.
* **Vấn đề:** Với 1 tỷ dòng và hàng triệu ứng viên, cái Hash Table này sẽ trở nên khổng lồ. Nếu nó không còn vừa trong RAM (vượt quá `work_mem` hay `sort_buffer_size`), Database sẽ phải "spill to disk" (ghi tạm xuống ổ cứng).
* **Hậu quả:** Tốc độ giảm từ micro-giây xuống mili-giây (chậm đi 1000 lần) do độ trễ của Disk I/O.


* **CPU Overhead:** Việc tính toán hàm băm (hashing) cho hàng tỷ giá trị và kiểm tra tính duy nhất (distinct) tiêu tốn rất nhiều chu kỳ CPU.

---

### 2. Giải bài toán bằng Self-Join (Tư duy giao thoa tập hợp)

Thay vì gom tất cả kỹ năng vào một chỗ rồi đếm, ta có thể tìm những người có kỹ năng A, sau đó "khớp" (join) họ với danh sách những người có kỹ năng B, rồi kỹ năng C.

**Code ví dụ (SQL):**

```sql
SELECT c1.candidate_id
FROM candidates c1
JOIN candidates c2 ON c1.candidate_id = c2.candidate_id
JOIN candidates c3 ON c1.candidate_id = c3.candidate_id
WHERE c1.skill = 'Python'
  AND c2.skill = 'Tableau'
  AND c3.skill = 'PostgreSQL';

```

---

### 3. Đánh đổi (Trade-off): JOIN 3 lần vs. GROUP BY - Cái nào tốn Memory hơn?

Đây chính là tinh thần của DDIA: **Không có giải pháp hoàn hảo, chỉ có sự đánh đổi.**

#### **Trường hợp JOIN 3 lần (Ưu tiên Memory):**

* **Cơ chế:** Nếu cột `(skill, candidate_id)` được đánh Index (B-Tree), Database sẽ thực hiện 3 lần quét Index cực nhanh để lấy ra 3 danh sách ID. Sau đó nó thực hiện **Index Join**.
* **Memory:** Database chỉ cần lưu trữ các con trỏ (pointers) hoặc các ID đang được khớp. Nó không cần giữ toàn bộ dữ liệu của 1 tỷ dòng trong một bảng băm khổng lồ.
* **Kết luận:** JOIN thường **tốn ít RAM hơn** GROUP BY trong trường hợp này vì nó lọc dữ liệu (Filter) cực mạnh ngay từ đầu nhờ Index.

#### **Trường hợp GROUP BY (Ưu tiên sự đơn giản):**

* **Cơ chế:** Nó phải quét vùng dữ liệu rộng hơn (tất cả các dòng có 1 trong 3 skills) rồi mới tiến hành phân loại.
* **Memory:** Tốn rất nhiều để duy trì trạng thái của các nhóm (groups).

---

### 4. Bài học khắc cốt ghi tâm (The Architect's Lesson)

Dựa trên **Chapter 3** của DDIA, bài học ở đây là về **Data Access Path**:

1. **Index-Friendly:** Phép JOIN 3 lần tận dụng được sức mạnh của **B-Tree Index** để loại bỏ 99.9% dữ liệu không liên quan ngay lập tức.
2. **Memory Management:** Khi dữ liệu vượt quá kích thước RAM, hãy ưu tiên các chiến lược "chia để trị" (như Join từng phần) thay vì dồn tất cả vào một phép tính Aggregation lớn.

---

### Mentor's Socratic Question (Câu hỏi nâng tầm):

> "Nếu bảng `candidates` được **Partitioning** (phân vùng) theo `skill` (mỗi kỹ năng nằm ở một ổ đĩa vật lý khác nhau - Chapter 6), việc bạn thực hiện **JOIN 3 lần** sẽ chuyển từ bài toán trên một máy thành bài toán **Distributed Join** (Join phân tán). Theo bạn, lúc này băng thông mạng (Network Bandwidth) hay RAM sẽ trở thành nút thắt cổ chai (bottleneck)?"

(Gợi ý: Hãy xem phần **Join Algorithms trong Distributed Systems** ở Chương 10 để thấy cách các kỹ trị gia xử lý hàng Petabyte dữ liệu nhé).

Bạn đã hiểu tại sao câu query cũ của bạn (dùng AND trên 1 dòng) lại ra "No data" so với bản chất của phép JOIN này chưa?
