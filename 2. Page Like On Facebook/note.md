### Bài học khắc cốt ghi tâm

- Join Predicates: Phép JOIN dùng để kết nối dữ liệu liên quan. Đừng bao giờ dùng JOIN với điều kiện != để tìm dữ liệu thiếu (missing data). Nó sẽ tạo ra một thảm họa về hiệu năng ($O(n^2)$) và kết quả sai bét.

- Nullability (Chapter 3): Luôn nhớ rằng trong Database quan hệ, sự vắng mặt của một mối quan hệ được biểu diễn qua NULL (khi dùng Outer Join) hoặc việc không tồn tại dòng dữ liệu.

- Think in Sets: Khi gặp bài toán "không nằm trong", hãy nghĩ ngay đến: LEFT JOIN + IS NULL, NOT IN, hoặc NOT EXISTS (select 1). Riêng về "Select 1", dưới góc nhìn của Maintainability và Scalability (Chapter 1 - DDIA):

  - Về mặt ngữ nghĩa (Semantics): NOT EXISTS diễn đạt trực tiếp ý định của bạn: "Lấy những trang mà không tồn tại bản ghi nào trong bảng Likes". Nó sát với ngôn ngữ tự nhiên và logic toán học hơn là việc LEFT JOIN rồi kiểm tra NULL.

  - Về mặt tài nguyên: Như đã nói ở trên, nó tiết kiệm I/O và CPU. Trong các hệ thống lớn, việc tránh quét dư thừa dữ liệu là yếu tố sống còn để hệ thống có thể scale (mở rộng).

### Question 1
> "Nếu cột page_id trong bảng page_likes không được đánh Index, thì liệu NOT EXISTS có còn nhanh không? Hay lúc đó nó cũng sẽ chậm y hệt như LEFT JOIN?"

**Answering**

Dưới góc nhìn của **DDIA (Chapter 3: Storage and Retrieval)**, khi không có Index, Database rơi vào trạng thái "mù lòa". Hãy cùng phân tích tại sao trong trường hợp này, `NOT EXISTS` hay `LEFT JOIN` đều "tệ" như nhau, và bản chất thực sự của nó là gì.


### 1. Khi không có Index: Cơn ác mộng Full Table Scan

**Liên hệ DDIA: Chapter 3 (B-Trees vs. LSM-Trees)**

Martin Kleppmann giải thích rằng Index giống như một bản đồ (metadata) giúp bạn tìm thấy dữ liệu mà không cần đọc toàn bộ file trên đĩa.

* **Cơ chế:** Nếu không có Index trên cột `page_id` của bảng `page_likes`, Database không thể thực hiện **Index Seek** (nhảy thẳng đến vị trí cần tìm).
* **Hành động:** Với mỗi trang (`page_id`) trong bảng `Pages`, Database buộc phải thực hiện một cú **Full Table Scan** trên bảng `page_likes` từ đầu đến cuối để xem có ID đó hay không.
* **Độ phức tạp:** Nếu bảng `Pages` có  dòng và bảng `page_likes` có  dòng, thuật toán lúc này trở thành **Nested Loop Join** với độ phức tạp .
* *Ví dụ:* 1.000 trang  1.000.000 lượt likes = 1 tỷ phép so sánh. Database của bạn sẽ "bốc khói".


### 2. Sự khác biệt giữa NOT EXISTS và LEFT JOIN lúc này là gì?

Dù cả hai đều phải quét bảng, nhưng vẫn có một sự khác biệt nhỏ về mặt "cố gắng" của Database Engine:

* **NOT EXISTS (vẫn giữ được tính Short-circuit):** Dù phải Scan, nhưng nếu may mắn lượt like của `page_id` đó nằm ngay đầu bảng `page_likes`, nó sẽ dừng lại ngay (Stop scanning).
* **LEFT JOIN (vượt quá khả năng kiểm soát):** Thông thường, `LEFT JOIN` sẽ cố gắng xây dựng một bảng kết quả tạm thời. Nếu Optimizer không đủ thông minh, nó có thể quét nhiều hơn mức cần thiết trước khi lọc `IS NULL`.

**Tuy nhiên:** Ở quy mô dữ liệu lớn, cái "may mắn" của `NOT EXISTS` không cứu vãn được hệ thống. Cả hai đều sẽ chậm đến mức không thể chấp nhận được.

---

### 3. Tư duy Engineer: Giải pháp thay thế (Trade-offs)

**Liên hệ DDIA: Chapter 10 (Batch Processing)**

Nếu bạn gặp tình huống bảng quá lớn và không thể đánh Index (ví dụ: dữ liệu đổ vào quá nhanh, đánh Index làm chậm tốc độ ghi - Write Amplification), một Database Engineer sẽ nghĩ đến:

* **Hash Join (Chapter 3):** Database sẽ quét bảng `page_likes` **một lần duy nhất** để xây dựng một **Hash Table** trong RAM. Sau đó quét bảng `Pages` và tra cứu vào Hash Table đó.
* *Độ phức tạp:* . Nhanh hơn khủng khiếp so với .
* *Đánh đổi:* Tốn rất nhiều RAM để giữ Hash Table.


* **Sort-Merge Join:** Sắp xếp cả hai bảng theo `page_id` rồi "khớp" chúng như hai dãy số đang chạy song song.
* *Đánh đổi:* Tốn chi phí CPU để sắp xếp (Sort).



---

### 4. Bài học "khắc cốt ghi tâm" số 5:

> **"A query without an index is a guess; a query with an index is a strategy."**

Khi viết bất kỳ câu lệnh nào có `WHERE`, `JOIN`, hay `EXISTS`, câu hỏi đầu tiên bạn phải tự hỏi không phải là "Nó có chạy đúng không?" mà là: **"Database sẽ tìm dữ liệu này bằng cách nào (Access Path)?"**

---

### Question 2

> "Bây giờ bạn đã biết Index giúp tìm kiếm nhanh. Nhưng trong **Chapter 3**, Martin có nói về **Write Amplification** (Sự khuếch đại ghi). Nếu tôi đánh Index cho **mọi cột** trong bảng để query nào cũng nhanh, thì hệ thống của tôi sẽ gặp thảm họa gì khi người dùng thực hiện `INSERT` hoặc `UPDATE` liên tục?"

Bạn đã nắm bắt được **mấu chốt của sự đánh đổi (Fundamental Trade-off)** trong thiết kế hệ thống dữ liệu rồi đấy!

Đúng như bạn nói, trong **Chapter 3: Storage and Retrieval**, Martin Kleppmann nhấn mạnh một quy luật bất biến: **"Any index typically slows down writes, because the index also needs to be updated every time data is written."** (Mọi index thường làm chậm thao tác ghi, vì index cũng cần được cập nhật mỗi khi dữ liệu được ghi vào).

Hãy cùng đào sâu bản chất của thảm họa này dưới góc nhìn của một Database Engineer:

#### 1. Hiện tượng Write Amplification (Khuếch đại ghi)

Khi bạn có một bảng với 5 indexes, một câu lệnh `INSERT` đơn giản không chỉ là ghi một dòng vào bảng chính (Heap file).

* **Bản chất:** Database phải thực hiện 6 thao tác ghi vật lý (1 vào bảng chính + 5 vào 5 cây B-Tree khác nhau).
* **Hệ quả:** Nếu các index này nằm trên các cột có dữ liệu ngẫu nhiên (như UUID), Database phải tìm đúng vị trí trong từng cây B-Tree trên đĩa cứng để chèn vào. Điều này gây ra rất nhiều thao tác **Random I/O**, thứ vốn là "kẻ thù" của hiệu năng ổ đĩa.

#### 2. Sự phân mảnh (Fragmentation) và Chi phí bảo trì

B-Tree (cấu trúc index phổ biến nhất) có các "Trang" (Pages) với kích thước cố định (thường là 8KB hoặc 16KB).

* **Vấn đề:** Khi bạn `INSERT` quá nhiều vào một trang đã đầy, Database phải thực hiện **Page Split** (Tách trang). Nó phải di chuyển dữ liệu, cấp phát trang mới và cập nhật lại các con trỏ ở các trang cha.
* **Tư duy Architect:** Việc đánh index quá đà sẽ khiến Database tiêu tốn tài nguyên CPU và I/O chỉ để "giữ cho các bộ chỉ mục được gọn gàng", thay vì thực sự xử lý dữ liệu cho người dùng.

#### 3. Đánh đổi (Trade-offs): Khi nào nên và không nên?

Dựa trên tinh thần của cuốn sách, chúng ta không bao giờ nói "Index là xấu", chúng ta nói về sự phù hợp:

* **Hệ thống OLTP (Online Transaction Processing):** Như ứng dụng đặt hàng, chuyển tiền. Tốc độ ghi là sống còn. Bạn phải **cực kỳ tiết kiệm** index. Chỉ đánh index trên những cột thực sự cần thiết cho các query phổ biến nhất.
* **Hệ thống OLAP (Online Analytical Processing):** Như các kho dữ liệu (Data Warehouse) phục vụ báo cáo. Dữ liệu thường được nạp theo đợt (batch) vào ban đêm và đọc cả ngày. Ở đây, bạn có thể đánh index "thả ga" để phục vụ các sếp xem báo cáo nhanh nhất có thể.

#### 4. Giải pháp thay thế: LSM-Trees (Lựa chọn của Big Data)

Nếu bạn không muốn đánh đổi tốc độ ghi, Martin Kleppmann giới thiệu một cấu trúc khác ở **Chapter 3**: **LSM-Trees (Log-Structured Merge-Trees)**.

* **Cách hoạt động:** Thay vì cập nhật trực tiếp vào B-Tree (tốn Random I/O), nó ghi dữ liệu vào một file log theo thứ tự thời gian (Sequential I/O - cực nhanh). Sau đó, nó mới gộp và sắp xếp lại ở nền (background).
* **Liên hệ thực tế:** Đây là lý do tại sao các Database như **Cassandra, RocksDB, hay Kafka** có tốc độ ghi khủng khiếp hơn hẳn MySQL hay PostgreSQL truyền thống.

---

### Question 3

Bạn đã hiểu về sự đánh đổi giữa Read và Write. Bây giờ hãy tưởng tượng:

> "Bạn có một cột `status` trong bảng `orders` chỉ có 2 giá trị: `PENDING` và `SHIPPED`. Bảng này có 1 tỷ dòng, trong đó 99% là `SHIPPED`. Nếu bạn đánh một Index thông thường lên cột `status` này để tìm các đơn hàng `PENDING`, liệu nó có hiệu quả không? Hay nó còn tệ hơn cả Full Table Scan?"

(Gợi ý: Hãy tìm hiểu về khái niệm **Index Selectivity** - Tính chọn lọc của Index. Một "bản đồ" mà chỗ nào cũng ghi giống nhau thì có giúp bạn tìm đường nhanh hơn không?)

Bạn đang chạm đúng vào một trong những khái niệm quan trọng nhất của việc tối ưu hóa truy vấn: **Index Selectivity (Tính chọn lọc của Index)**.

Dưới góc nhìn của **DDIA (Chapter 3)**, lý do vì sao dùng Index cho cột Low Cardinality (như `status`) lại có thể **tệ hơn cả Full Table Scan** nằm ở sự khác biệt giữa **Random I/O** và **Sequential I/O**.

---

### 1. Bản chất của "Cú nhảy" (The Jump Overhead)

Khi bạn dùng một Secondary Index (Index phụ) để tìm dữ liệu, Database thực hiện 2 bước:

* **Bước 1:** Tìm trong cây B-Tree để lấy ra các "con trỏ" (pointers/row IDs) của các dòng thỏa mãn (ví dụ: các đơn hàng `PENDING`).
* **Bước 2:** Với **mỗi** con trỏ tìm được, Database phải "nhảy" vào bảng dữ liệu chính (Heap file hoặc Clustered Index) để lấy toàn bộ thông tin của dòng đó.

**Vấn đề là:** Các dòng `PENDING` này thường nằm rải rác khắp nơi trên ổ đĩa.

* Nếu có 100.000 đơn hàng `PENDING`, Database phải thực hiện **100.000 cú nhảy ngẫu nhiên (Random I/O)**.
* Trong khi đó, **Full Table Scan** thực hiện **Sequential I/O** (đọc tuần tự). Ổ đĩa (ngay cả SSD và đặc biệt là HDD) đọc tuần tự nhanh hơn rất nhiều so với việc nhảy lò cò đi tìm từng mảnh dữ liệu.

---

### 2. Khi nào thì Index trở thành "Gánh nặng"?

Trong **Chapter 3**, Martin Kleppmann có nhắc đến việc các Storage Engine phải cân nhắc chi phí.

* **Với High Cardinality (Email):** Query chỉ trả về **1 dòng**. 1 cú nhảy Random I/O là cực kỳ rẻ so với việc đọc toàn bộ bảng 1 tỷ dòng. Index thắng tuyệt đối.
* **Với Low Cardinality (Status):** Nếu 20-30% bảng là `PENDING`, số lượng cú nhảy Random I/O lớn đến mức tổng thời gian "nhảy" sẽ lâu hơn cả thời gian quét toàn bộ bảng từ đầu đến cuối.

**Quy tắc ngón tay cái (Rule of thumb):** Nếu một câu truy vấn trả về hơn **10-20%** tổng số dòng trong bảng, các Database Optimizer (như của MySQL hay PostgreSQL) thường sẽ **bỏ qua Index** và quyết định chạy Full Table Scan cho nhanh.

---

### 3. Ví dụ thực tế: Cuốn sách nấu ăn

Hãy tưởng tượng bạn có một cuốn sách nấu ăn 1000 trang:

* **Trường hợp 1 (High Cardinality):** Bạn tìm công cụ "Nồi áp suất điện model X". Chỉ có 1 trang nhắc tới. Bạn xem mục lục (Index), lật đúng trang đó. **Nhanh!**
* **Trường hợp 2 (Low Cardinality):** Bạn tìm các công thức có dùng "Muối". Có 800 trang dùng muối.
* Nếu bạn dùng mục lục: Bạn đọc danh sách 800 số trang, sau đó lật đi lật lại 800 lần. Bạn sẽ chóng mặt và mất thời gian kinh khủng.
* Nếu bạn quét (Full Scan): Bạn chỉ việc lật từ trang 1 đến trang 1000, trang nào thấy chữ "Muối" thì dừng lại đọc. Cách này thực tế sẽ **nhanh hơn và đỡ mỏi tay hơn**.



---

### 4. Tư duy Architect: Làm sao để Index cột Low Cardinality hiệu quả?

Dựa trên **DDIA**, nếu bạn vẫn bắt buộc phải query nhanh trên cột Low Cardinality, bạn có các lựa chọn đánh đổi sau:

1. **Covering Index (Chapter 3):** Bạn tạo Index trên cả `(status, order_id, customer_id)`.
* **Lợi ích:** Toàn bộ dữ liệu bạn cần đã nằm ngay trong Index. Database không cần "nhảy" vào bảng chính nữa. Nó triệt tiêu hoàn toàn Random I/O.


2. **Bitmap Index (Chapter 3):** Thường dùng trong các OLAP Database. Nó dùng các chuỗi bit (0 và 1) để đại diện cho sự tồn tại của giá trị. Việc tính toán trên bit cực nhanh và tốn ít bộ nhớ.
3. **Filtered Index (Partial Index):** Trong Postgres, bạn có thể tạo index chỉ cho những dòng có `status = 'PENDING'`.
* `CREATE INDEX idx_pending ON orders (status) WHERE status = 'PENDING';`
* **Lợi ích:** Index này sẽ rất nhỏ vì nó bỏ qua 99% các dòng `SHIPPED`.



---

### Queston 4

Bạn đã hiểu tại sao Random I/O là "kẻ giết chết" hiệu năng khi dùng Index trên cột Low Cardinality. Vậy tôi đố bạn một câu liên quan đến **Hardware (Phần cứng)**:

> "Với sự phổ biến của **SSD** (có tốc độ Random I/O rất tốt so với HDD), liệu chúng ta có nên bớt lo lắng về việc đánh Index trên các cột có tính chọn lọc thấp không? Hay bản chất kiến trúc phần mềm vẫn ưu tiên Sequential I/O hơn?"

(Gợi ý: Đọc lại phần **SSTables và LSM-Trees** ở Chapter 3 để xem các kỹ sư Google/Facebook ưu tiên kiểu ghi/đọc nào nhé!)

### Answering
Đây là một câu hỏi mang tính "vĩ mô" về sự giao thoa giữa phần cứng (Hardware) và phần mềm (Software). Dưới đây là cách giải thích chi tiết bằng tiếng Anh, giữ đúng tinh thần của cuốn **DDIA**:

### The Question:

"With the rise of **SSDs** (which have much better Random I/O speeds compared to HDDs), should we worry less about indexing low-selectivity columns? Or does software architecture still fundamentally prioritize Sequential I/O?"

---

### The Deep Answer (DDIA Mindset):

**1. SSDs vs. HDDs: The Performance Gap**
In **Chapter 3**, Martin Kleppmann discusses storage engines. While it's true that SSDs lack the physical "seeking" overhead of a spinning disk (HDD), they are not "magic."

* **Random I/O on SSD:** It is indeed orders of magnitude faster than HDD.
* **Sequential I/O on SSD:** Even on modern NVMe SSDs, **Sequential I/O is still significantly faster** than Random I/O (often 10x to 100x faster). This is due to internal controller optimizations, bus bandwidth (PCIe), and the way flash memory pages are read in blocks.

**2. The Software Architecture Perspective (Why Sequential is King)**
Software architecture still prioritizes Sequential I/O for several core reasons mentioned in DDIA:

* **Throughput (Băng thông):** Sequential access allows the operating system and the hardware to "read ahead" (prefetching). If you are scanning a table sequentially, the CPU can process data while the disk controller is already fetching the next block. Random I/O breaks this pipeline.
* **LSM-Trees (Log-Structured Merge-Trees):** This is a key example from **Chapter 3**. Modern databases like Cassandra or RocksDB convert Random Writes into Sequential Writes to gain massive performance. If Random I/O were "cheap enough," we wouldn't need complex structures like LSM-Trees or SSTables.

**3. The Low-Selectivity Index Trap (Still applies!)**
Even on an SSD, the **"Index Join Overhead"** still exists:

* **The Amplification Issue:** To read one row via a secondary index, the DB must read an index page AND then a data page. If you are fetching 30% of a 1-billion-row table, you are still forcing the SSD to perform millions of tiny, independent lookups.
* **The Cost of Metadata:** Managing the index (Write Amplification) and the CPU overhead of traversing the B-Tree for millions of entries often outweighs the benefit when selectivity is low.

---

### Summary for a Database Engineer (In English):

> "While SSDs reduce the **penalty** of Random I/O, they do not make it **free**. Sequential I/O remains the gold standard for high-throughput data processing. In modern system design, we still prefer **Full Table Scans** (or Columnar Scans) for low-selectivity data because it maximizes hardware bandwidth and allows for efficient CPU caching and prefetching. **The hardware has changed, but the fundamental trade-off between Random and Sequential access remains.**"


### Question 5
> "Nếu bảng page_likes của bạn cực kỳ lớn (ví dụ hàng tỷ lượt likes) và được Partitioned theo user_id, nhưng bảng pages lại nằm ở một node khác. Theo bạn, việc dùng NOT EXISTS có còn nhanh không khi Database phải thực hiện Network Request qua lại giữa các node để kiểm tra sự tồn tại của ID? Bạn sẽ tối ưu nó như thế nào?"
