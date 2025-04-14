## **Spotoolfy 应用重构计划书**

**目标:** 对 Spotoolfy 应用进行数据库和代码重构，以实现以下核心功能：

1. **歌词片段保存:** 在添加笔记时，仅保存当前播放位置相关的歌词片段，而非完整歌词。  
2. **最近播放上下文轮播图:** 在 Library 页面顶部轮播图显示最近播放的 15 个上下文（专辑/播放列表）的封面。  
3. **记录评分调整:** 将用户笔记的评分（rating）从文本类型改为整数类型，并设置默认值为 3。  
4. **翻译功能:** 保持现有歌词翻译数据库结构不变。

### **一、最终数据库结构**

重构后，应用将包含以下四个核心数据表：

1. **tracks** 表: (保留并可能微调)  
   * 存储歌曲元数据（ID, 名称, 歌手, 专辑, 封面 URL, 时间戳等）。  
2. **records** 表: (字段类型和默认值调整)  
   * 存储用户笔记（关联 tracks 表）。  
   * lyricsSnapshot 字段将存储**歌词片段**。  
   * rating 字段将改为 **INTEGER** 类型，并设置 **DEFAULT 3**。  
3. **translations** 表: (保留，无变化)  
   * 存储歌词翻译结果（关联 tracks 表）。  
4. **play\_contexts** 表: (新增)  
   * 存储播放上下文信息（专辑/播放列表 URI, 类型, 名称, 封面 URL）以及**最后播放时间戳**，用于驱动轮播图。

### **二、功能实现步骤**

#### **1\. 歌词片段保存 (无变化)**

* **目标:** 将 records 表 lyricsSnapshot 字段的存储内容从完整歌词改为空白，并添加 TODO，等待后续处理。

#### **2\. 最近播放上下文轮播图 (无变化)**

* **目标:** 在 Library 页面顶部轮播图显示最近播放的 15 个上下文。  
* **方法:** 新增 play\_contexts 表，记录上下文信息和时间戳，修改 MyCarouselView 从此表获取数据。  
* **具体步骤:**  
  1. **lib/data/database\_helper.dart**:  
     * 新增 play\_contexts 表（包含 contextUri PK, contextType, contextName, imageUrl, lastPlayedAt）。  
     * 新增 insertOrUpdatePlayContext 和 getRecentPlayContexts 方法。  
  2. **lib/providers/spotify\_provider.dart**:  
     * 修改 refreshCurrentTrack，在检测到上下文时，准备 contextData 并调用 localDbProvider.insertOrUpdatePlayContext。  
  3. **lib/providers/local\_database\_provider.dart**:  
     * 新增 \_recentContexts 状态及 getter。  
     * 实现 insertOrUpdatePlayContext 方法。  
     * 新增 fetchRecentContexts 方法更新 \_recentContexts。  
  4. **lib/providers/library\_provider.dart**:  
     * 移除与轮播图相关的 \_recentlyPlayed 状态。  
  5. **lib/pages/library.dart** (**MyCarouselView**):  
     * 修改为直接依赖 LocalDatabaseProvider。  
     * 调用 localDbProvider.fetchRecentContexts 加载数据。  
     * 使用 localDbProvider.recentContexts 构建轮播图。  
     * onTap 事件调用 spotifyProvider.playContext。

#### **3\. 记录评分调整 (新增步骤)**

* **目标:** 将 records.rating 字段改为 INTEGER DEFAULT 3。  
* **方法:** 修改数据库、模型、数据处理和 UI 相关代码。  
* **具体步骤:**  
  1. **lib/data/database\_helper.dart**:  
     * 修改 \_onCreate 方法中 CREATE TABLE records 语句，将 rating TEXT 改为 rating INTEGER DEFAULT 3。  
     * 调整 insertRecord (虽然 toMap 会处理，但确认类型匹配)。  
     * 调整 getRecordsForTrack (虽然 fromMap 会处理，但确认类型匹配)。  
  2. **lib/models/record.dart**:  
     * 修改 rating 字段类型：final int? rating;。  
     * 修改 fromMap：rating: map\['rating'\] as int?,。  
     * 修改 toMap：'rating': rating,。  
     * 修改构造函数以接受 int? rating。  
  3. **lib/providers/local\_database\_provider.dart**:  
     * 修改 addRecord 方法签名，接受 required int? rating 参数。  
     * 在创建 newRecord 对象时传递 int? rating。  
  4. **lib/widgets/add\_note.dart** (**AddNoteSheetState**):  
     * 移除 String? \_selectedRating 状态变量。  
     * **新增**状态变量 int? \_selectedRatingValue;。  
     * 在 \_handleSubmit 方法中，将 \_selectedRatingValue 传递给 localDbProvider.addRecord 的 rating 参数。如果 \_selectedRatingValue 为 null，则数据库将使用默认值 3。  
     * **需要**在 AddNoteSheet 中添加 Ratings Widget（如果之前没有的话），或者确保现有的 Ratings Widget 能更新 \_selectedRatingValue。  
  5. **lib/widgets/materialui.dart** (**Ratings** widget):  
     * 修改 initialRating 参数类型为 int?。  
     * 修改 \_getRatingIndex 方法，根据传入的 int? initialRating (例如 1, 2, 3\) 返回对应的 Segmented Button 索引 (0, 1, 2)。如果 initialRating 为 null 或无效值，可以选择一个默认索引（例如 1 代表 neutral）。  
     * onRatingChanged 回调保持不变，仍然传递索引 (0, 1, 2)。  
     * **重要:** 在使用此 Widget 的地方 (如 AddNoteSheet)，需要将 onRatingChanged 返回的索引 (0, 1, 2\) 映射为你想要的整数值 (例如 1, 2, 3\) 来更新 \_selectedRatingValue。例如：  
       Ratings(  
         initialRating: \_selectedRatingValue, // Pass the int rating  
         onRatingChanged: (selectedIndex) {  
           setState(() {  
             // Map index 0, 1, 2 to rating 1, 2, 3  
             \_selectedRatingValue \= selectedIndex \+ 1;  
           });  
         },  
       )

  6. **lib/widgets/notes.dart** (**NotesDisplay**):  
     * 修改 itemBuilder 中显示评分的部分。不再是显示文本 record.rating。  
     * 需要根据 record.rating 的整数值 (1, 2, 3 或 null/默认值3) 来显示对应的图标或其他视觉元素。例如，可以使用 if/else 或 switch 语句根据 record.rating 的值选择不同的 Icon。  
  7. **lib/pages/roam.dart**:  
     * 修改 itemBuilder 中显示评分的部分（卡片右下角）。  
     * 与 NotesDisplay 类似，根据 record\['rating'\] 的整数值显示对应的视觉元素，而不是直接显示数字或旧的文本。

#### **4\. 翻译数据库 (无变化)**

* **目标:** 保持不变。  
* **方法:** 无需进行修改。

### **三、总结**

本计划书 V2 包含了实现歌词片段保存、最近播放上下文轮播图以及将记录评分改为整数（默认值为 3）所需进行的数据库调整和代码修改。请按照各步骤进行实施。